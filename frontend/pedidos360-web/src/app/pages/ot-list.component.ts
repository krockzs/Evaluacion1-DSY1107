import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { ApiService } from '../services/api.service';
import { OtResumen } from '../models';

@Component({
  standalone: true,
  imports: [CommonModule, RouterLink],
  template: `
    <div class="page-head">
      <div>
        <h1>Órdenes de trabajo</h1>
        <p>Vista basada en V_OT_RESUMEN.</p>
      </div>

      <a class="button" routerLink="/ots/nueva">Nueva OT</a>
    </div>

    <div *ngIf="loading" class="card">
      Cargando…
    </div>

    <div *ngIf="error" class="error">
      {{ error }}
    </div>

    <div class="table-wrap" *ngIf="!loading && !error">
      <table>
        <thead>
          <tr>
            <th>OT</th>
            <th>Cliente</th>
            <th>Patente</th>
            <th>Descripción</th>
            <th>Total</th>
            <th>Ítems</th>
            <th>Subtotal</th>
          </tr>
        </thead>

        <tbody>
          <tr *ngFor="let ot of data">
            <td>
              <a [routerLink]="['/ots', ot.otId]">
                {{ ot.otId }}
              </a>
            </td>

            <td>{{ ot.clienteId }}</td>
            <td>{{ ot.patente }}</td>
            <td>{{ ot.descripcion }}</td>

            <td>
              {{ ot.total | currency:'CLP':'symbol-narrow':'1.0-0' }}
            </td>

            <td>{{ ot.nitems }}</td>

            <td>
              {{ (ot.subtotalCalc ?? 0) | currency:'CLP':'symbol-narrow':'1.0-0' }}
            </td>
          </tr>
        </tbody>
      </table>

      <div class="card" *ngIf="data.length === 0">
        No existen órdenes de trabajo.
      </div>
    </div>
  `
})
export class OtListComponent implements OnInit {

  data: OtResumen[] = [];
  loading = true;
  error = '';

  constructor(private api: ApiService) {}

  ngOnInit(): void {
    this.api.ots().subscribe({
      next: value => {
        this.data = value;
        this.loading = false;
      },
      error: e => {
        console.error('Error cargando OT:', e);

        this.error =
          `Error ${e.status}: ${e.error?.message || e.message}`;

        this.loading = false;
      }
    });
  }
}