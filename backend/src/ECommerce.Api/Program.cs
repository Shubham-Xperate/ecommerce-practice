using System.Text;
using ECommerce.Api.Data;
using ECommerce.Api.Models;
using ECommerce.Api.Services;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.AspNetCore.Diagnostics.HealthChecks;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;

var builder = WebApplication.CreateBuilder(args);

// ---------------------------------------------------------------------------
// EF Core / SQL Server
// ---------------------------------------------------------------------------
// Connection string comes from configuration key ConnectionStrings:DefaultConnection.
// Locally this is set in appsettings.Development.json; in containers/Kubernetes it
// is overridden via the env var ConnectionStrings__DefaultConnection (standard
// ASP.NET Core double-underscore -> nested-key configuration binding), so no
// extra wiring is required here.
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

// ---------------------------------------------------------------------------
// ASP.NET Core Identity
// ---------------------------------------------------------------------------
// Reasonable-but-not-excessive password/lockout rules for a teaching sample.
builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
{
    options.Password.RequireDigit = true;
    options.Password.RequireUppercase = false;
    options.Password.RequireNonAlphanumeric = false;
    options.Password.RequiredLength = 8;

    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(5);
    options.Lockout.MaxFailedAccessAttempts = 5;

    options.User.RequireUniqueEmail = true;
})
    .AddEntityFrameworkStores<AppDbContext>()
    .AddDefaultTokenProviders();

// ---------------------------------------------------------------------------
// JWT Bearer authentication
// ---------------------------------------------------------------------------
// Key/Issuer/Audience come from Jwt:Key / Jwt:Issuer / Jwt:Audience, overridable
// via Jwt__Key / Jwt__Issuer / Jwt__Audience env vars (e.g. injected from a
// Kubernetes Secret). Never commit real values - see appsettings.Production.json.
var jwtKey = builder.Configuration["Jwt:Key"] ?? string.Empty;
var jwtIssuer = builder.Configuration["Jwt:Issuer"];
var jwtAudience = builder.Configuration["Jwt:Audience"];

builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme)
    .AddJwtBearer(options =>
    {
        options.TokenValidationParameters = new TokenValidationParameters
        {
            ValidateIssuer = true,
            ValidIssuer = jwtIssuer,
            ValidateAudience = true,
            ValidAudience = jwtAudience,
            ValidateLifetime = true,
            ValidateIssuerSigningKey = true,
            IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(jwtKey)),
            ClockSkew = TimeSpan.FromMinutes(1)
        };
    });

builder.Services.AddAuthorization();

// ---------------------------------------------------------------------------
// CORS
// ---------------------------------------------------------------------------
// Single approach used throughout: one config key, Cors:AllowedOrigin, holding a
// comma-separated list of allowed origins (overridable via Cors__AllowedOrigin).
// This keeps the config surface simple - one key to set per environment - while
// still allowing multiple origins (e.g. a staging URL and a prod URL) if needed.
var allowedOrigins = (builder.Configuration["Cors:AllowedOrigin"] ?? "http://localhost:4200")
    .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

const string CorsPolicyName = "AllowFrontend";

builder.Services.AddCors(options =>
{
    options.AddPolicy(CorsPolicyName, policy =>
    {
        policy.WithOrigins(allowedOrigins)
            .AllowAnyHeader()
            .AllowAnyMethod();
    });
});

builder.Services.AddControllers();

// ---------------------------------------------------------------------------
// Swagger / OpenAPI - includes a JWT bearer security definition so the Swagger
// UI "Authorize" button can attach an Authorization: Bearer <token> header.
// ---------------------------------------------------------------------------
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new OpenApiInfo { Title = "ECommerce API", Version = "v1" });

    options.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme
    {
        Name = "Authorization",
        Type = SecuritySchemeType.Http,
        Scheme = "Bearer",
        BearerFormat = "JWT",
        In = ParameterLocation.Header,
        Description = "Enter a valid JWT token. Example: Bearer eyJhbGciOi..."
    });

    options.AddSecurityRequirement(new OpenApiSecurityRequirement
    {
        {
            new OpenApiSecurityScheme
            {
                Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" }
            },
            Array.Empty<string>()
        }
    });
});

// ---------------------------------------------------------------------------
// Health checks
// ---------------------------------------------------------------------------
// The DB check is tagged "ready" so it can be selectively included/excluded by
// the two health endpoints mapped below (liveness vs readiness semantics).
builder.Services.AddHealthChecks()
    .AddDbContextCheck<AppDbContext>(name: "database", tags: new[] { "ready" });

builder.Services.AddScoped<IJwtTokenService, JwtTokenService>();

var app = builder.Build();

// ---------------------------------------------------------------------------
// Development-only conveniences: Swagger UI, and auto-applying EF migrations.
// ---------------------------------------------------------------------------
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();

    // Auto-migrate only in Development for a fast local inner loop. In real
    // production environments, migrations should be run as a controlled,
    // auditable pipeline step (e.g. an Azure DevOps release step or K8s Job)
    // BEFORE the new app version starts serving traffic - not on every pod
    // startup, which could race across multiple replicas.
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

// ---------------------------------------------------------------------------
// Idempotent role seeding. Runs on every startup (cheap: checks existence
// before creating), so both Development and Production always have the
// baseline "Admin" and "Customer" roles available without a separate manual
// step. Kept simple for this teaching sample rather than a full seeding
// framework.
// ---------------------------------------------------------------------------
using (var scope = app.Services.CreateScope())
{
    var roleManager = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
    string[] roles = { "Admin", "Customer" };

    foreach (var role in roles)
    {
        if (!await roleManager.RoleExistsAsync(role))
        {
            await roleManager.CreateAsync(new IdentityRole(role));
        }
    }
}

app.UseCors(CorsPolicyName);

app.UseAuthentication();
app.UseAuthorization();

app.MapControllers();

// ---------------------------------------------------------------------------
// Health endpoints
// ---------------------------------------------------------------------------
// /health (readiness-style, full check): runs every registered health check,
// including the DB check. Suitable for a K8s readiness probe - if the DB is
// unreachable, the pod is taken out of the Service's load-balancing rotation
// until it recovers, without being killed.
app.MapHealthChecks("/health", new HealthCheckOptions
{
    Predicate = _ => true
});

// /health/live (liveness): Predicate = _ => false means "run none of the
// registered checks, just confirm the process can accept a request and
// respond". This is intentional - a K8s liveness probe should only ask
// "is this process alive/hung?", never "is a downstream dependency healthy?".
// If liveness depended on the DB, a transient DB blip would cause Kubernetes
// to kill and restart otherwise-healthy pods instead of simply routing traffic
// away from them (which is what the readiness probe on /health is for).
app.MapHealthChecks("/health/live", new HealthCheckOptions
{
    Predicate = _ => false
});

// No hardcoded URL here: the port is controlled entirely by ASPNETCORE_URLS,
// set to http://+:8080 by the Dockerfile/Kubernetes Deployment in containers,
// or by launchSettings.json for local `dotnet run`.
app.Run();
