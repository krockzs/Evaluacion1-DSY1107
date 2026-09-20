import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { MsalService } from '@azure/msal-angular';
import { ApiService } from '../services/api.service';
import { UserClaims } from '../models';

@Component({
  standalone: true,
  imports: [CommonModule],
  template: `
    <section class="hero">
      <h1>Evaluación Parcial 1</h1>
      <p>Angular + MSAL + BFF Spring Boot + microservicios + Oracle.</p>
      <button *ngIf="!logged" (click)="login()">Iniciar sesión</button>
    </section>
    <section *ngIf="logged" class="card">
      <h2>Claims del token</h2>
      <button (click)="loadClaims()">Leer roles y scopes desde el BFF</button>
      <pre *ngIf="claims">{{claims | json}}</pre>
    </section>
  `
})
export class HomeComponent {
  claims?: UserClaims;

  constructor(private msal: MsalService, private api: ApiService) {}

  get logged() {
    return this.msal.instance.getAllAccounts().length > 0;
  }

  login() {
    this.msal.loginRedirect();
  }

  loadClaims() {
    this.api.me().subscribe(v => this.claims = v);
  }
}
