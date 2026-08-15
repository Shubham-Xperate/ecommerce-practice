namespace ECommerce.Api.DTOs;

public record CreateOrderDto(List<CreateOrderItemDto> Items);
