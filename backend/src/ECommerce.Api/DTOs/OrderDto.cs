using ECommerce.Api.Models;

namespace ECommerce.Api.DTOs;

public record OrderDto(
    int Id,
    DateTime OrderDate,
    OrderStatus Status,
    decimal TotalAmount,
    List<OrderItemDto> Items);
