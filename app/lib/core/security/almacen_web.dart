import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'device_keys.dart';

/// Implementación Web: la clave privada es un `CryptoKey` **no exportable** de WebCrypto,
/// persistido en IndexedDB (D-29). La clave pública (JWK) se guarda en `localStorage`.

const String _nombreDb = 'campus-carnet';
const String _almacenDb = 'claves';
const String _clavePrivada = 'device-key';
const String _clavePublicaLocal = 'campus.device.public.jwk';

web.SubtleCrypto get _subtle => web.window.crypto.subtle;

JSObject _mapaJs(Map<String, Object?> valores) => valores.jsify() as JSObject;

JSArray<JSString> _usos(List<String> valores) => valores.map((valor) => valor.toJS).toList().toJS;

JSObject _buffer(List<int> bytes) => Uint8List.fromList(bytes).toJS as JSObject;

Future<T> _esperarPeticion<T extends JSAny?>(web.IDBRequest peticion) {
  final completador = Completer<T>();
  peticion.onsuccess = ((web.Event _) {
    completador.complete(peticion.result as T);
  }).toJS;
  peticion.onerror = ((web.Event _) {
    completador.completeError(StateError('IndexedDB respondió con error'));
  }).toJS;
  return completador.future;
}

Future<web.IDBDatabase> _abrirBase() async {
  final peticion = web.window.indexedDB.open(_nombreDb, 1);
  peticion.onupgradeneeded = ((web.Event _) {
    final base = peticion.result as web.IDBDatabase;
    if (!base.objectStoreNames.contains(_almacenDb)) {
      base.createObjectStore(_almacenDb);
    }
  }).toJS;
  return _esperarPeticion<web.IDBDatabase>(peticion);
}

Future<web.CryptoKey?> _leerPrivada() async {
  final base = await _abrirBase();
  try {
    final transaccion = base.transaction(_usos([_almacenDb]), 'readonly');
    final almacen = transaccion.objectStore(_almacenDb);
    final resultado = await _esperarPeticion<JSAny?>(almacen.get(_clavePrivada.toJS));
    if (resultado == null) return null;
    return resultado as web.CryptoKey;
  } finally {
    base.close();
  }
}

Future<void> _guardarPrivada(web.CryptoKey privada) async {
  final base = await _abrirBase();
  try {
    final transaccion = base.transaction(_usos([_almacenDb]), 'readwrite');
    final almacen = transaccion.objectStore(_almacenDb);
    await _esperarPeticion<JSAny?>(almacen.put(privada, _clavePrivada.toJS));
  } finally {
    base.close();
  }
}

Future<(web.CryptoKey, web.CryptoKey)> _generarPar() async {
  final algoritmo = _mapaJs({'name': 'ECDSA', 'namedCurve': 'P-256'});
  final resultado =
      await _subtle.generateKey(algoritmo, false, _usos(['sign', 'verify'])).toDart as JSObject;
  return (
    resultado.getProperty<web.CryptoKey>('privateKey'.toJS),
    resultado.getProperty<web.CryptoKey>('publicKey'.toJS),
  );
}

Future<Map<String, dynamic>> _exportarPublica(web.CryptoKey publica) async {
  final exportada = await _subtle.exportKey('jwk', publica).toDart;
  final mapa = (exportada.dartify() as Map<Object?, Object?>).map(
    (clave, valor) => MapEntry<String, dynamic>('$clave', valor),
  );
  return {
    'kty': 'EC',
    'crv': 'P-256',
    'x': mapa['x'],
    'y': mapa['y'],
  };
}

Future<List<int>> _firmar(web.CryptoKey privada, List<int> entrada) async {
  final algoritmo = _mapaJs({
    'name': 'ECDSA',
    'hash': {'name': 'SHA-256'},
  });
  final firma = await _subtle.sign(algoritmo, privada, _buffer(entrada)).toDart;
  final buffer = (firma as JSArrayBuffer).toDart;
  return buffer.asUint8List();
}

class VerificadorEs256Web implements VerificadorEs256 {
  const VerificadorEs256Web();

  @override
  Future<bool> verificar(Map<String, dynamic> clavePublicaJwk, List<int> datos, List<int> firma) async {
    final algoritmo = _mapaJs({
      'name': 'ECDSA',
      'hash': {'name': 'SHA-256'},
    });
    final clave = await _subtle
        .importKey(
          'jwk',
          _mapaJs(clavePublicaJwk),
          _mapaJs({'name': 'ECDSA', 'namedCurve': 'P-256'}),
          false,
          _usos(['verify']),
        )
        .toDart;
    final resultado = await _subtle
        .verify(algoritmo, clave, _buffer(firma), _buffer(datos))
        .toDart;
    return (resultado as JSBoolean).toDart;
  }
}

class AlmacenClavesWeb implements AlmacenClavesDispositivo {
  web.CryptoKey? _privadaEnMemoria;
  Map<String, dynamic>? _publicaEnMemoria;

  /// `true` si la clave se pudo persistir; si no, dura solo esta pestaña (D-29).
  bool persistente = true;

  Future<ClaveDispositivo> _aClave(web.CryptoKey privada, Map<String, dynamic> publica) async {
    return ClaveDispositivo(
      clavePublicaJwk: publica,
      huella: huellaDeJwk(publica),
      firmarEntrada: (entrada) => _firmar(privada, entrada),
    );
  }

  @override
  Future<ClaveDispositivo?> cargar() async {
    try {
      final privada = await _leerPrivada();
      final publicaTexto = web.window.localStorage.getItem(_clavePublicaLocal);
      if (privada == null || publicaTexto == null) return null;
      return _aClave(privada, jsonDecode(publicaTexto) as Map<String, dynamic>);
    } catch (_) {
      persistente = false;
      if (_privadaEnMemoria != null && _publicaEnMemoria != null) {
        return _aClave(_privadaEnMemoria!, _publicaEnMemoria!);
      }
      return null;
    }
  }

  @override
  Future<ClaveDispositivo> generar() async {
    final (privada, publica) = await _generarPar();
    final publicaJwk = await _exportarPublica(publica);
    _privadaEnMemoria = privada;
    _publicaEnMemoria = publicaJwk;
    try {
      await _guardarPrivada(privada);
      web.window.localStorage.setItem(_clavePublicaLocal, jsonEncode(publicaJwk));
    } catch (_) {
      persistente = false;
    }
    return _aClave(privada, publicaJwk);
  }

  @override
  Future<void> borrar() async {
    _privadaEnMemoria = null;
    _publicaEnMemoria = null;
    web.window.localStorage.removeItem(_clavePublicaLocal);
    try {
      final base = await _abrirBase();
      final transaccion = base.transaction(_usos([_almacenDb]), 'readwrite');
      await _esperarPeticion<JSAny?>(transaccion.objectStore(_almacenDb).delete(_clavePrivada.toJS));
      base.close();
    } catch (_) {
      // Sin persistencia no hay nada que borrar.
    }
  }
}

AlmacenClavesDispositivo crearAlmacenDeClaves() => AlmacenClavesWeb();

VerificadorEs256 crearVerificadorEs256() => const VerificadorEs256Web();
