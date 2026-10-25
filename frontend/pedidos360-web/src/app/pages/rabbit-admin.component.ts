import { CommonModule } from '@angular/common';
import { Component } from '@angular/core';
import { FormsModule } from '@angular/forms';
import { Observable, finalize } from 'rxjs';
import { RabbitAdminApiService } from '../services/rabbit-admin-api.service';

type Tab = 'queues' | 'exchanges' | 'bindings' | 'messages' | 'tests';

@Component({
  selector: 'app-rabbit-admin',
  standalone: true,
  imports: [CommonModule, FormsModule],
  styles: [`
    .admin { max-width: 1100px; margin: 0 auto; padding: 16px; }
    .tabs { display: flex; flex-wrap: wrap; gap: 10px; margin-bottom: 20px; }
    .tabs button.active { font-weight: bold; border: 2px solid currentColor; }
    .layout { display: grid; grid-template-columns: repeat(auto-fit,minmax(250px,1fr)); gap: 14px; }
    .panel { padding: 18px; border: 1px solid #aaa5; border-radius: 12px; margin-bottom: 14px; }
    label { display: block; margin: 10px 0; font-size: .93rem; }
    input,select,textarea { display: block; width: 100%; box-sizing: border-box; padding: 9px; margin-top: 5px; }
    textarea { min-height: 105px; font-family: monospace; }
    button { margin: 4px; }
    pre { white-space: pre-wrap; overflow-wrap: anywhere; background: #20252b; color: #f3f5f6; padding: 18px; border-radius: 8px; max-height: 520px; overflow: auto; }
    .warning { padding: 12px; border-left: 4px solid #e8a23b; background: #daa52014; }
    .error { color: #b51b2b; }
  `],
  template: `
    <section class="admin">
      <h1>RabbitMQ — Consola administrativa</h1>
      <p class="warning">Acceso mediante Microsoft Entra ID. Las operaciones realizadas aquí modifican RabbitMQ en AWS.</p>
      <div class="tabs">
        <button type="button" *ngFor="let item of tabs" [class.active]="tab === item.id" (click)="tab=item.id">{{item.title}}</button>
      </div>
      <div class="layout" *ngIf="tab==='queues'">
        <div class="panel">
          <h2>Colas</h2>
          <button (click)="run(api.queues())" [disabled]="busy">Listar colas y estados</button>
          <label>Nombre <input [(ngModel)]="queueName" /></label>
          <button (click)="run(api.queue(queueName))" [disabled]="busy || !queueName.trim()">Consultar cola</button>
          <button (click)="run(api.createQueue({name:queueName,durable:true}))" [disabled]="busy || !queueName.trim()">Crear cola</button>
          <button (click)="removeQueue()" [disabled]="busy || !queueName.trim()">Eliminar cola</button>
        </div>
      </div>
      <div class="layout" *ngIf="tab==='exchanges'">
        <div class="panel">
          <h2>Exchanges</h2>
          <button (click)="run(api.exchanges())" [disabled]="busy">Listar exchanges</button>
          <label>Nombre <input [(ngModel)]="exchangeName" /></label>
          <label>Tipo <select [(ngModel)]="exchangeType"><option value="direct">direct</option><option value="topic">topic</option><option value="fanout">fanout</option></select></label>
          <button (click)="run(api.createExchange({name:exchangeName,type:exchangeType,durable:true}))" [disabled]="busy || !exchangeName.trim()">Crear exchange</button>
          <button (click)="removeExchange()" [disabled]="busy || !exchangeName.trim()">Eliminar exchange</button>
        </div>
      </div>
      <div class="layout" *ngIf="tab==='bindings'">
        <div class="panel">
          <h2>Bindings</h2>
          <button (click)="run(api.bindings())" [disabled]="busy">Listar bindings</button>
          <label>Exchange origen <input [(ngModel)]="exchangeName" /></label>
          <label>Cola destino <input [(ngModel)]="queueName" /></label>
          <label>Routing key <input [(ngModel)]="routingKey" /></label>
          <button (click)="run(api.createBinding({source:exchangeName,destination:queueName,routingKey:routingKey}))" [disabled]="busy">Crear binding</button>
          <p>Eliminar bindings exige el <code>properties_key</code> devuelto por RabbitMQ:</p>
          <label>Properties key <input [(ngModel)]="propertiesKey" /></label>
          <button (click)="removeBinding()" [disabled]="busy || !propertiesKey.trim()">Eliminar binding</button>
        </div>
      </div>
      <div *ngIf="tab==='messages'" class="panel">
        <h2>Inspector de mensajes</h2>
        <p class="warning">La inspección extrae y reencola mensajes; puede alterar temporalmente el orden o la entrega. Usar preferentemente en colas de prueba.</p>
        <label>Cola <input [(ngModel)]="queueName" /></label>
        <label>Cantidad (1 a 10) <input type="number" min="1" max="10" [(ngModel)]="count" /></label>
        <button (click)="run(api.messages(queueName,count))" [disabled]="busy || !queueName.trim() || count<1 || count>10">Inspeccionar y reencolar</button>
      </div>
      <div *ngIf="tab==='tests'" class="panel">
        <h2>Publicar mensaje de prueba</h2>
        <p>Esta acción publica un mensaje real cuando el backend esté conectado. Utilizar identificadores de prueba.</p>
        <label>Exchange <input [(ngModel)]="exchangeName" /></label>
        <label>Routing key <input [(ngModel)]="routingKey" /></label>
        <label>Payload JSON <textarea [(ngModel)]="payload"></textarea></label>
        <button (click)="publish()" [disabled]="busy">Publicar mensaje</button>
        <button (click)="tab='messages'">Ir al inspector</button>
      </div>
      <p *ngIf="busy">Ejecutando solicitud…</p>
      <p *ngIf="error" class="error" role="alert">{{error}}</p>
      <section class="panel" aria-live="polite"><h2>Respuesta del servidor</h2><pre>{{output}}</pre></section>
    </section>
  `
})
export class RabbitAdminComponent {
  readonly tabs: {id: Tab; title: string}[] = [
    {id:'queues',title:'Colas'}, {id:'exchanges',title:'Exchanges'},
    {id:'bindings',title:'Bindings'}, {id:'messages',title:'Mensajes'}, {id:'tests',title:'Pruebas'}
  ];
  tab: Tab = 'queues'; busy = false; error = ''; output = 'Sin consultas todavía';
  queueName = 'ot.notifications.queue'; exchangeName = 'ot.notifications.exchange';
  routingKey = 'ot.created'; exchangeType = 'direct'; propertiesKey = ''; count = 1;
  payload = JSON.stringify({type:'NotificarClienteOtCreada',otId:'OT-TEST-001',clienteId:'TEST',canal:'email'},null,2);
  constructor(public readonly api: RabbitAdminApiService) {}
  run(call: Observable<unknown>): void {
    this.error=''; this.busy=true;
    call.pipe(finalize(()=>this.busy=false)).subscribe({
      next: value => this.output=JSON.stringify(value,null,2) ?? 'Operación completada',
      error: err => { this.error=`Solicitud fallida (HTTP ${err.status ?? 'desconocido'}). ${err.status === 403 ? 'Operación rechazada por la política de autorización.' : err.status === 401 ? 'Sesión inválida o expirada.' : err.status === 502 || err.status === 503 ? 'RabbitMQ no disponible.' : 'Revisar respuesta del servidor.'}`; this.output=JSON.stringify(err.error ?? {},null,2); }
    });
  }
  publish(): void {
    try {
      JSON.parse(this.payload);
    } catch { this.error='Payload JSON inválido'; return; }
    this.run(this.api.publish({exchange:this.exchangeName,routingKey:this.routingKey,payload:this.payload}));
  }
  removeQueue(): void { if(confirm(`¿Eliminar cola ${this.queueName}?`)) this.run(this.api.deleteQueue(this.queueName)); }
  removeExchange(): void { if(confirm(`¿Eliminar exchange ${this.exchangeName}?`)) this.run(this.api.deleteExchange(this.exchangeName)); }
  removeBinding(): void { if(confirm('¿Eliminar binding?')) this.run(this.api.deleteBinding(this.exchangeName,this.queueName,this.propertiesKey)); }
}
