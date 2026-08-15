import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { Router, RouterLink } from '@angular/router';
import { CartService } from '../../core/cart.service';
import { AuthService } from '../../core/auth.service';
import { OrdersService } from '../../core/orders.service';
import { CreateOrderRequest } from '../../core/models';

@Component({
  selector: 'app-cart',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './cart.component.html',
  styleUrl: './cart.component.css'
})
export class CartComponent {
  submitting = false;
  error: string | null = null;
  successOrderId: number | null = null;

  constructor(
    public cartService: CartService,
    private authService: AuthService,
    private ordersService: OrdersService,
    private router: Router
  ) {}

  get items() {
    return this.cartService.getItems()();
  }

  get total() {
    return this.cartService.total();
  }

  updateQuantity(productId: number, quantityValue: string | number): void {
    const quantity = Number(quantityValue);
    this.cartService.updateQuantity(productId, quantity);
  }

  remove(productId: number): void {
    this.cartService.removeFromCart(productId);
  }

  checkout(): void {
    if (!this.authService.isLoggedIn()) {
      this.router.navigateByUrl('/login');
      return;
    }

    if (this.items.length === 0) {
      return;
    }

    this.submitting = true;
    this.error = null;

    const request: CreateOrderRequest = {
      items: this.items.map((i) => ({ productId: i.product.id, quantity: i.quantity }))
    };

    this.ordersService.createOrder(request).subscribe({
      next: (order) => {
        this.successOrderId = order.id;
        this.cartService.clearCart();
        this.submitting = false;
      },
      error: () => {
        this.error = 'Failed to place order. Please try again.';
        this.submitting = false;
      }
    });
  }
}
