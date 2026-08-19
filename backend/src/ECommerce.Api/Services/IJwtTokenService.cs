using ECommerce.Api.Models;

namespace ECommerce.Api.Services;

public interface IJwtTokenService
{
    string GenerateToken(ApplicationUser user, IList<string> roles);
}
