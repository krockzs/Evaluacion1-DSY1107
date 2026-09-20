export interface OtResumen {
  otId: string;
  clienteId: string;
  patente: string;
  descripcion: string | null;
  total: number;
  createdAt: string;
  nitems: number;
  subtotalCalc: number | null;
}

export interface Ot {
  otId: string;
  clienteId: string;
  patente: string;
  descripcion: string | null;
  total: number;
  createdAt: string;
  updatedAt: string | null;
}

export interface OtItem {
  itemId: number;
  otId: string;
  concepto: string;
  cantidad: number;
  precioUnit: number;
  subtotal: number;
  createdAt: string;
}

export interface OtEvent {
  eventId: number;
  otId: string;
  eventType: string;
  payloadJson: string;
  createdAt: string;
}

export interface NotificationLog {
  logId: number;
  otId: string;
  clienteId: string;
  canal: string;
  payloadJson: string;
  createdAt: string;
}

export interface OtDetail {
  ot: Ot;
  items: OtItem[];
  events: OtEvent[];
  notifications: NotificationLog[];
}

export interface UserClaims {
  name: string;
  username: string;
  roles: string[];
  scopes: string;
}