namespace ECommerce.Api.DTOs;

public record RegisterDto(string Email, string Password, string? FirstName, string? LastName);
