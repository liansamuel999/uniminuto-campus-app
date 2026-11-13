/** Reglas de entrega (§6.2, D-29): ENVIADA, TARDIA con 24 h de gracia, o rechazada. */

export type EstadoEntrega = 'ENVIADA' | 'TARDIA';

export function calcularEstadoEntrega(params: {
  creadaEnCliente: Date;
  cierraEn: Date;
  recibidaEnServidor: Date;
  graciaHoras: number;
}): { aceptada: true; estado: EstadoEntrega } | { aceptada: false; motivo: 'FUERA_DE_PLAZO' } {
  const { creadaEnCliente, cierraEn, recibidaEnServidor, graciaHoras } = params;
  const limite = new Date(cierraEn.getTime() + graciaHoras * 60 * 60 * 1000);
  if (recibidaEnServidor.getTime() > limite.getTime()) {
    return { aceptada: false, motivo: 'FUERA_DE_PLAZO' };
  }
  return { aceptada: true, estado: creadaEnCliente <= cierraEn ? 'ENVIADA' : 'TARDIA' };
}
