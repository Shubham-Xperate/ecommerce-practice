// DTOs (Data Transfer Objects) exist to decouple the public API contract from
// our EF Core entities. This avoids over-posting/under-posting vulnerabilities
// (clients can't set fields they shouldn't, like Ids or navigation-driven data),
// and prevents serialization issues like infinite navigation-property cycles
// (e.g. Product -> Category -> Products -> Category -> ...).
namespace ECommerce.Api.DTOs;

public record CategoryDto(int Id, string Name);
