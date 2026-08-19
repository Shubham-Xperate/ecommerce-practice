export interface Product {
  id: number;
  name: string;
  description: string;
  price: number;
  stock: number;
  categoryId: number;
  categoryName: string;
}

export interface Category {
  id: number;
  name: string;
}

export interface PagedResult<T> {
  items: T[];
  totalCount: number;
  page: number;
  pageSize: number;
}

export interface RegisterRequest {
  email: string;
  password: string;
}

export interface LoginRequest {
  email: string;
  password: string;
}

export interface LoginResponse {
  token: string;
  expiresAt: string;
}

export interface OrderItem {
  productId: number;
  productName: string;
  quantity: number;
  unitPrice: number;
}

export interface Order {
  id: number;
  createdAt: string;
  status: string;
  items: OrderItem[];
  total: number;
}

export interface CreateOrderItem {
  productId: number;
  quantity: number;
}

export interface CreateOrderRequest {
  items: CreateOrderItem[];
}

// Client-side cart line item. Keeps a reference to the full Product so the
// cart/checkout UI can display name/price without re-fetching.
export interface CartItem {
  product: Product;
  quantity: number;
}
