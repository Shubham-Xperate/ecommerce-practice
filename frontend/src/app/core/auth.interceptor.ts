import { HttpInterceptorFn } from '@angular/common/http';
import { inject } from '@angular/core';
import { AuthService } from './auth.service';

// Endpoints that should never receive an Authorization header, even if a
// token happens to be present (keeps requests tidy / avoids sending a stale
// or irrelevant token to public auth endpoints).
const PUBLIC_PATHS = ['/auth/login', '/auth/register'];

export const authInterceptor: HttpInterceptorFn = (req, next) => {
  const auth = inject(AuthService);
  const token = auth.getToken();

  const isPublicEndpoint = PUBLIC_PATHS.some((path) => req.url.includes(path));

  if (token && !isPublicEndpoint) {
    const cloned = req.clone({
      setHeaders: { Authorization: `Bearer ${token}` }
    });
    return next(cloned);
  }

  return next(req);
};
