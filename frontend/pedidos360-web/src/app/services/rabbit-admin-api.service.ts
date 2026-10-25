import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { environment } from '../../environments/environment';

/** Todas las operaciones pasan por el BFF, que todavía debe enrutar y autorizar /api/admin. */
@Injectable({ providedIn: 'root' })
export class RabbitAdminApiService {
  private readonly base = `${environment.bffUrl}/api/admin`;
  constructor(private readonly http: HttpClient) {}
  queues(): Observable<unknown> { return this.http.get(`${this.base}/queues`); }
  queue(name: string): Observable<unknown> { return this.http.get(`${this.base}/queues/${encodeURIComponent(name)}`); }
  messages(name: string, count: number): Observable<unknown> {
    return this.http.get(`${this.base}/queues/${encodeURIComponent(name)}/messages`, {
      params: new HttpParams().set('count', count)
    });
  }
  createQueue(body: unknown): Observable<unknown> { return this.http.post(`${this.base}/queues`, body); }
  deleteQueue(name: string): Observable<unknown> { return this.http.delete(`${this.base}/queues/${encodeURIComponent(name)}`); }
  exchanges(): Observable<unknown> { return this.http.get(`${this.base}/exchanges`); }
  createExchange(body: unknown): Observable<unknown> { return this.http.post(`${this.base}/exchanges`, body); }
  deleteExchange(name: string): Observable<unknown> { return this.http.delete(`${this.base}/exchanges/${encodeURIComponent(name)}`); }
  bindings(): Observable<unknown> { return this.http.get(`${this.base}/bindings`); }
  createBinding(body: unknown): Observable<unknown> { return this.http.post(`${this.base}/bindings`, body); }
  deleteBinding(source: string, queue: string, key: string): Observable<unknown> {
    return this.http.delete(`${this.base}/bindings/${encodeURIComponent(source)}/${encodeURIComponent(queue)}/${encodeURIComponent(key)}`);
  }
  publish(body: unknown): Observable<unknown> { return this.http.post(`${this.base}/publish`, body); }
}
