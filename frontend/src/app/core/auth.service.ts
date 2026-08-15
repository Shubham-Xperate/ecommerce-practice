import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable, tap } from 'rxjs';
import { ConfigService } from './config.service';
import { LoginRequest, LoginResponse, RegisterRequest } from './models';

const TOKEN_KEY = 'ecommerce_token';
const EXPIRES_KEY = 'ecommerce_token_expires_at';

/**
 * Manages the auth token for the current session.
 *
 * Storage tradeoff (deliberate):
 * We persist the token to `sessionStorage`, NOT `localStorage`.
 *
 * sessionStorage is NOT a magic fix for XSS - if an attacker manages to run
 * arbitrary JS in this page (e.g. via a dependency supply-chain attack or an
 * injected script), that JS can read sessionStorage just as easily as
 * localStorage. Neither is "secure storage" in the way an httpOnly cookie is,
 * because httpOnly cookies are never exposed to JavaScript at all - that
 * would be the more robust mitigation, but it requires the backend to set
 * and validate a cookie (and handle CSRF protections), which is out of scope
 * for this teaching project's REST contract.
 *
 * What sessionStorage DOES buy us over localStorage: it scopes the token's
 * lifetime to the browser tab. It's cleared when the tab is closed, so a
 * stolen/leaked token from a shared or public machine doesn't silently
 * persist across browser restarts indefinitely the way localStorage would.
 * It's a defense-in-depth / blast-radius reduction, not a fix for XSS itself.
 *
 * We also keep the token in a private in-memory field as the primary source
 * of truth during the page's lifetime (avoids re-parsing storage on every
 * read), and hydrate that field from sessionStorage once on construction so
 * a page refresh doesn't spuriously log the user out.
 */
@Injectable({ providedIn: 'root' })
export class AuthService {
  private token: string | null = null;
  private expiresAt: string | null = null;

  constructor(private http: HttpClient, private config: ConfigService) {
    // Hydrate in-memory state from sessionStorage on service construction
    // (i.e. on app bootstrap / page load), so refreshing the page doesn't
    // lose the logged-in session.
    this.token = sessionStorage.getItem(TOKEN_KEY);
    this.expiresAt = sessionStorage.getItem(EXPIRES_KEY);
  }

  login(email: string, password: string): Observable<LoginResponse> {
    const body: LoginRequest = { email, password };
    return this.http.post<LoginResponse>(`${this.config.apiUrl}/auth/login`, body).pipe(
      tap((res) => {
        this.token = res.token;
        this.expiresAt = res.expiresAt;
        sessionStorage.setItem(TOKEN_KEY, res.token);
        sessionStorage.setItem(EXPIRES_KEY, res.expiresAt);
      })
    );
  }

  register(email: string, password: string): Observable<void> {
    const body: RegisterRequest = { email, password };
    return this.http.post<void>(`${this.config.apiUrl}/auth/register`, body);
  }

  logout(): void {
    this.token = null;
    this.expiresAt = null;
    sessionStorage.removeItem(TOKEN_KEY);
    sessionStorage.removeItem(EXPIRES_KEY);
  }

  isLoggedIn(): boolean {
    if (!this.token) {
      return false;
    }
    if (this.expiresAt && new Date(this.expiresAt).getTime() <= Date.now()) {
      // Token has expired; treat the user as logged out.
      this.logout();
      return false;
    }
    return true;
  }

  getToken(): string | null {
    return this.token;
  }
}
