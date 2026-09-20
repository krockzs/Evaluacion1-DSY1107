import { InteractionType, PublicClientApplication } from '@azure/msal-browser';
import { MsalGuardConfiguration, MsalInterceptorConfiguration } from '@azure/msal-angular';
import { environment } from '../environments/environment';

export function msalInstance() {
  return new PublicClientApplication({
    auth: { clientId: environment.clientId, authority: `https://login.microsoftonline.com/${environment.tenantId}`, redirectUri: environment.redirectUri, postLogoutRedirectUri: environment.redirectUri },
    cache: { cacheLocation: 'sessionStorage' }
  });
}
export function msalGuardConfig(): MsalGuardConfiguration {
  return { interactionType: InteractionType.Redirect, authRequest: { scopes: [environment.apiScopeRead, environment.apiScopeWrite] } };
}
export function msalInterceptorConfig(): MsalInterceptorConfiguration {
  const protectedResourceMap = new Map<string, Array<string>>();
  protectedResourceMap.set(`${environment.bffUrl}/api/*`, [environment.apiScopeRead, environment.apiScopeWrite]);
  return { interactionType: InteractionType.Redirect, protectedResourceMap };
}
