import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { ConfigService } from './config.service';
import { CreateOrderRequest, Order } from './models';

@Injectable({ providedIn: 'root' })
export class OrdersService {
  constructor(private http: HttpClient, private config: ConfigService) {}

  getOrders(): Observable<Order[]> {
    return this.http.get<Order[]>(`${this.config.apiUrl}/orders`);
  }

  createOrder(request: CreateOrderRequest): Observable<Order> {
    return this.http.post<Order>(`${this.config.apiUrl}/orders`, request);
  }
}
