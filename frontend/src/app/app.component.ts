import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { Router, RouterLink, RouterOutlet } from '@angular/router';
import { AuthService } from './core/auth.service';
import { CartService } from './core/cart.service';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [CommonModule, RouterLink, RouterOutlet],
  templateUrl: './app.component.html',
  styleUrl: './app.component.css'
})
export class AppComponent {
  constructor(
    public auth: AuthService,
    public cart: CartService,
    private router: Router
  ) {}

  get cartCount(): number {
    return this.cart.getItems()().reduce((sum, i) => sum + i.quantity, 0);
  }

  logout(): void {
    this.auth.logout();
    this.router.navigateByUrl('/');
  }
}
