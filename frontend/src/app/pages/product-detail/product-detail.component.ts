import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { ActivatedRoute, Router, RouterLink } from '@angular/router';
import { ProductsService } from '../../core/products.service';
import { CartService } from '../../core/cart.service';
import { Product } from '../../core/models';

@Component({
  selector: 'app-product-detail',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './product-detail.component.html',
  styleUrl: './product-detail.component.css'
})
export class ProductDetailComponent implements OnInit {
  product: Product | null = null;
  quantity = 1;
  loading = false;
  error: string | null = null;
  addedMessage: string | null = null;

  constructor(
    private route: ActivatedRoute,
    private router: Router,
    private productsService: ProductsService,
    private cartService: CartService
  ) {}

  ngOnInit(): void {
    const idParam = this.route.snapshot.paramMap.get('id');
    const id = idParam ? Number(idParam) : NaN;
    if (isNaN(id)) {
      this.error = 'Invalid product id.';
      return;
    }

    this.loading = true;
    this.productsService.getProduct(id).subscribe({
      next: (product) => {
        this.product = product;
        this.loading = false;
      },
      error: () => {
        this.error = 'Failed to load product.';
        this.loading = false;
      }
    });
  }

  addToCart(): void {
    if (!this.product) {
      return;
    }
    this.cartService.addToCart(this.product, this.quantity);
    this.addedMessage = `Added ${this.quantity} x ${this.product.name} to cart.`;
  }

  goToCart(): void {
    this.router.navigateByUrl('/cart');
  }
}
