import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Error de la API con el código del contrato `{codigo, mensaje}` (§7.7, D-17).
class ApiException implements Exception {
  ApiException({required this.codigo, required this.mensaje, this.estado});

  final String codigo;
  final String mensaje;
  final int? estado;

  bool get esNoAutorizado => estado == 401;
  bool get esProhibido => estado == 403;
  bool get esSinRed => codigo == 'SIN_RED';

  @override
  String toString() => 'ApiException($codigo, $estado): $mensaje';
}

/// Cliente HTTP de la API con el ID Token adjunto en cada petición (§3.2).
class ApiClient {
  ApiClient({
    required String baseUrl,
    Future<String?> Function()? tokenProvider,
    Dio? dio,
  })  : _tokenProvider = tokenProvider,
        _dio = dio ??
            Dio(
              BaseOptions(
                baseUrl: baseUrl,
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 20),
                headers: const {'Accept': 'application/json'},
              ),
            ) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (opciones, manejador) async {
          final token = await _tokenProvider?.call();
          if (token != null && token.isNotEmpty) {
            opciones.headers['Authorization'] = 'Bearer $token';
          }
          manejador.next(opciones);
        },
      ),
    );
  }

  final Dio _dio;
  final Future<String?> Function()? _tokenProvider;

  Dio get dio => _dio;

  /// Sube bytes a una URL prefirmada del datalake (MinIO/S3).
  ///
  /// Se usa un cliente **sin** el interceptor del token: S3 rechaza la petición si recibe
  /// `Authorization` además de la firma de la URL prefirmada. Este era el motivo por el que
  /// «Adjuntar archivo» fallaba en la app aunque la URL prefirmada funcionara en el navegador.
  Future<void> putBinario(String url, Uint8List bytes, {required String mime}) async {
    final cliente = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 60),
        sendTimeout: const Duration(seconds: 60),
      ),
    );
    try {
      final respuesta = await cliente.put<void>(
        url,
        data: bytes,
        options: Options(
          headers: {'Content-Type': mime},
          responseType: ResponseType.plain,
        ),
      );
      if ((respuesta.statusCode ?? 0) >= 400) {
        throw ApiException(
          codigo: 'ERROR_SUBIDA',
          mensaje: 'No se pudo subir el archivo (HTTP ${respuesta.statusCode}).',
          estado: respuesta.statusCode,
        );
      }
    } on DioException catch (error) {
      throw ApiException(
        codigo: 'ERROR_SUBIDA',
        mensaje:
            'No se pudo subir el archivo (${error.response?.statusCode ?? 'sin conexión'}). '
            'Revisa el datalake e inténtalo otra vez.',
        estado: error.response?.statusCode,
      );
    }
  }

  Future<Map<String, dynamic>> getJson(String ruta, {Map<String, dynamic>? parametros}) {
    return _ejecutar(() => _dio.get<Map<String, dynamic>>(ruta, queryParameters: parametros));
  }

  Future<Map<String, dynamic>> postJson(String ruta, {Object? cuerpo}) {
    return _ejecutar(() => _dio.post<Map<String, dynamic>>(ruta, data: cuerpo));
  }

  Future<Map<String, dynamic>> putJson(String ruta, {Object? cuerpo}) {
    return _ejecutar(() => _dio.put<Map<String, dynamic>>(ruta, data: cuerpo));
  }

  Future<Map<String, dynamic>> deleteJson(String ruta) {
    return _ejecutar(() => _dio.delete<Map<String, dynamic>>(ruta));
  }

  /// GET que devuelve una lista JSON (p. ej. espacios reservables).
  Future<List<dynamic>> getList(String ruta) async {
    try {
      final respuesta = await _dio.get<List<dynamic>>(ruta);
      return respuesta.data ?? const [];
    } on DioException catch (error) {
      throw _traducir(error);
    }
  }

  /// Ejecuta la petición y homogeneiza los errores en [ApiException] (D-17).
  Future<Map<String, dynamic>> _ejecutar(
    Future<Response<Map<String, dynamic>>> Function() peticion,
  ) async {
    try {
      final respuesta = await peticion();
      return respuesta.data ?? const <String, dynamic>{};
    } on DioException catch (error) {
      throw _traducir(error);
    }
  }

  ApiException _traducir(DioException error) {
    final respuesta = error.response;
    final datos = respuesta?.data;

    if (datos is Map<String, dynamic> && datos['codigo'] is String) {
      return ApiException(
        codigo: datos['codigo'] as String,
        mensaje: '${datos['mensaje'] ?? 'Error de la API'}',
        estado: respuesta?.statusCode,
      );
    }

    final esDeRed = error.type == DioExceptionType.connectionError ||
        error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout;
    if (esDeRed) {
      return ApiException(
        codigo: 'SIN_RED',
        mensaje: 'No hay conexión con el servidor. Revisa la red e inténtalo de nuevo.',
      );
    }

    return ApiException(
      codigo: respuesta?.statusCode == 401 ? 'NO_AUTORIZADO' : 'ERROR_CLIENTE',
      mensaje: error.message ?? 'Error inesperado al llamar a la API',
      estado: respuesta?.statusCode,
    );
  }
}
