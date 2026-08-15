import { Injectable, computed, signal } from '@angular/core';
import { CartItem, Product } from './models';

/**
 * In-memory shopping cart. No backend persistence - the cart lives only for
 * the current page session and is sent to the backend as a single
 * POST /api/orders payload at checkout time (see OrdersService.createOrder).
 */
@Injectable({ providedIn: 'root' })
export class CartService {
  private items = signal<CartItem[]>([]);

  readonly total = computed(() =>
    this.items().reduce((sum, item) => sum + item.product.price * item.quantity, 0)
  );

  getItems() {
    return this.items;
  }

  addToCart(product: Product, quantity: number): void {
    if (quantity <= 0) {
      return;
    }
    const current = this.items();
    const existing = current.find((i) => i.product.id === product.id);

    if (existing) {
      this.items.set(
        current.map((i) =>
          i.product.id === product.id ? { ...i, quantity: i.quantity + quantity } : i
        )
      );
    } else {
      this.items.set([...current, { product, quantity }]);
    }
  }

  removeFromCart(productId: number): void {
    this.items.set(this.items().filter((i) => i.product.id !== productId));
  }

  updateQuantity(productId: number, quantity: number): void {
    if (quantity <= 0) {
      this.removeFromCart(productId);
      return;
    }
    this.items.set(
      this.items().map((i) => (i.product.id === productId ? { ...i, quantity } : i))
    );
  }

  clearCart(): void {
    this.items.set([]);
  }
}
