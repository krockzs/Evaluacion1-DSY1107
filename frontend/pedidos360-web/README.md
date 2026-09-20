# pedidos360-web

Frontend Angular con MSAL.

Antes de ejecutar, completar `src/environments/environment.ts` con:

- Tenant ID;
- Client ID de la SPA;
- Client ID de la API;
- scopes `ot.read` y `ot.write` expuestos por Microsoft Entra ID.

```bash
npm install
npm start
```

Redirect URI local esperado: `http://localhost:4200/`.
