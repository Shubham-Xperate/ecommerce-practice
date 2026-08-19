import { Injectable } from '@angular/core';
import { HttpClient, HttpParams } from '@angular/common/http';
import { Observable } from 'rxjs';
import { ConfigService } from './config.service';
import { Category, PagedResult, Product } from './models';

@Injectable({ providedIn: 'root' })
export class ProductsService {
  constructor(private http: HttpClient, private config: ConfigService) {}

  getProducts(
    categoryId: number | null,
    page: number,
    pageSize: number
  ): Observable<PagedResult<Product>> {
    let params = new HttpParams().set('page', page).set('pageSize', pageSize);
    if (categoryId !== null) {
      params = params.set('category', categoryId);
    }
    return this.http.get<PagedResult<Product>>(`${this.config.apiUrl}/products`, { params });
  }

  getProduct(id: number): Observable<Product> {
    return this.http.get<Product>(`${this.config.apiUrl}/products/${id}`);
  }

  getCategories(): Observable<Category[]> {
    return this.http.get<Category[]>(`${this.config.apiUrl}/categories`);
  }
}
