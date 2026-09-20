import { Routes } from '@angular/router';
import { MsalGuard } from '@azure/msal-angular';
import { HomeComponent } from './pages/home.component';
import { OtListComponent } from './pages/ot-list.component';
import { OtDetailComponent } from './pages/ot-detail.component';
import { OtCreateComponent } from './pages/ot-create.component';

export const routes: Routes = [
  { path: '', component: HomeComponent },
  { path: 'ots', component: OtListComponent, canActivate: [MsalGuard] },
  { path: 'ots/nueva', component: OtCreateComponent, canActivate: [MsalGuard] },
  { path: 'ots/:id', component: OtDetailComponent, canActivate: [MsalGuard] },
  { path: '**', redirectTo: '' }
];
