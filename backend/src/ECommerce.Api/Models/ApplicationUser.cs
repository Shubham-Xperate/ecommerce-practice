using Microsoft.AspNetCore.Identity;

namespace ECommerce.Api.Models;

// Extends the built-in Identity user with a couple of profile fields.
// Keeping this minimal on purpose for a teaching sample.
public class ApplicationUser : IdentityUser
{
    public string? FirstName { get; set; }

    public string? LastName { get; set; }
}
