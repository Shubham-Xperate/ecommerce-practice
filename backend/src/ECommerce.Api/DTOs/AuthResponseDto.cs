namespace ECommerce.Api.DTOs;

public record AuthResponseDto(string Token, string Email, DateTime Expiration);
