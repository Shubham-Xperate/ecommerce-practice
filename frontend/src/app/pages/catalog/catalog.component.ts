import { Component, OnInit } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { RouterLink } from '@angular/router';
import { ProductsService } from '../../core/products.service';
import { Category, PagedResult, Product } from '../../core/models';

@Component({
  selector: 'app-catalog',
  standalone: true,
  imports: [CommonModule, FormsModule, RouterLink],
  templateUrl: './catalog.component.html',
  styleUrl: './catalog.component.css'
})
export class CatalogComponent implements OnInit {
  categories: Category[] = [];
  products: Product[] = [];

  selectedCategoryId: number | null = null;
  page = 1;
  pageSize = 8;
  totalCount = 0;

  loading = false;
  error: string | null = null;

  constructor(private productsService: ProductsService) {}

  ngOnInit(): void {
    this.productsService.getCategories().subscribe({
      next: (categories) => (this.categories = categories),
      error: () => (this.error = 'Failed to load categories.')
    });
    this.loadProducts();
  }

  get totalPages(): number {
    return Math.max(1, Math.ceil(this.totalCount / this.pageSize));
  }

  onCategoryChange(): void {
    this.page = 1;
    this.loadProducts();
  }

  goToPage(page: number): void {
    if (page < 1 || page > this.totalPages) {
      return;
    }
    this.page = page;
    this.loadProducts();
  }

  private loadProducts(): void {
    this.loading = true;
    this.error = null;
    this.productsService.getProducts(this.selectedCategoryId, this.page, this.pageSize).subscribe({
      next: (result: PagedResult<Product>) => {
        this.products = result.items;
        this.totalCount = result.totalCount;
        this.loading = false;
      },
      error: () => {
        this.error = 'Failed to load products.';
        this.loading = false;
      }
    });
  }
}
