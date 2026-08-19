namespace ECommerce.Api.DTOs;

// Generic wrapper for paginated list endpoints.
public record PagedResult<T>(
    List<T> Items,
    int TotalCount,
    int PageNumber,
    int PageSize);
