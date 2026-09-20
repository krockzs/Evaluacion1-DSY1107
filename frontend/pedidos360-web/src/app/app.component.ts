import { Component, OnInit } from '@angular/core';
import { RouterLink, RouterOutlet } from '@angular/router';
import { CommonModule } from '@angular/common';
import { MsalService } from '@azure/msal-angular';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterOutlet],
  template: `
    <header>
      <div class="brand">Pedidos360 <small>TALLERPRO360</small></div>
      <nav>
        <a routerLink="/">Inicio</a>
        <a *ngIf="loggedIn" routerLink="/ots">Órdenes</a>
        <a *ngIf="loggedIn" routerLink="/ots/nueva">Nueva OT</a>
      </nav>
      <div>
        <button *ngIf="!loggedIn" (click)="login()">Ingresar con Microsoft</button>
        <button *ngIf="loggedIn" class="secondary" (click)="logout()">Cerrar sesión</button>
      </div>
    </header>
    <main><router-outlet /></main>
  `
})
export class AppComponent implements OnInit {
  loggedIn = false;

  constructor(private msal: MsalService) {}

  ngOnInit() {
    this.msal.instance.enableAccountStorageEvents();
    this.msal.handleRedirectObservable().subscribe({
      next: result => {
        if (result?.account) {
          this.msal.instance.setActiveAccount(result.account);
        }
        if (!this.msal.instance.getActiveAccount()) {
          const first = this.msal.instance.getAllAccounts()[0];
          if (first) {
            this.msal.instance.setActiveAccount(first);
          }
        }
        this.refresh();
      },
      error: err => console.error(err)
    });
  }

  refresh() {
    this.loggedIn = this.msal.instance.getAllAccounts().length > 0;
  }

  login() {
    this.msal.loginRedirect();
  }

  logout() {
    this.msal.logoutRedirect();
  }
}
