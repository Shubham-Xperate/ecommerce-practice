using ECommerce.Api.Models;
using Microsoft.AspNetCore.Identity.EntityFrameworkCore;
using Microsoft.EntityFrameworkCore;

namespace ECommerce.Api.Data;

// IdentityDbContext<ApplicationUser> gives us all the standard Identity tables
// (AspNetUsers, AspNetRoles, AspNetUserRoles, etc.) alongside our own domain tables.
public class AppDbContext : IdentityDbContext<ApplicationUser>
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options)
    {
    }

    public DbSet<Category> Categories => Set<Category>();

    public DbSet<Product> Products => Set<Product>();

    public DbSet<Order> Orders => Set<Order>();

    public DbSet<OrderItem> OrderItems => Set<OrderItem>();

    protected override void OnModelCreating(ModelBuilder builder)
    {
        // Must run first so Identity's own entity configuration is applied
        // before we layer our own Fluent API configuration on top.
        base.OnModelCreating(builder);

        // ---------- Category ----------
        builder.Entity<Category>(entity =>
        {
            entity.Property(c => c.Name)
                .IsRequired()
                .HasMaxLength(100);

            entity.HasMany(c => c.Products)
                .WithOne(p => p.Category)
                .HasForeignKey(p => p.CategoryId)
                // Prevent deleting a category that still has products attached.
                .OnDelete(DeleteBehavior.Restrict);
        });

        // ---------- Product ----------
        builder.Entity<Product>(entity =>
        {
            entity.Property(p => p.Name)
                .IsRequired()
                .HasMaxLength(200);

            entity.Property(p => p.Description)
                .HasMaxLength(1000);

            entity.Property(p => p.Price)
                .HasPrecision(18, 2);
        });

        // ---------- Order ----------
        builder.Entity<Order>(entity =>
        {
            entity.Property(o => o.TotalAmount)
                .HasPrecision(18, 2);

            // Enum stored as its string name for readability in the database
            // (e.g. "Pending" instead of 0) - easier to read/debug directly in SQL.
            entity.Property(o => o.Status)
                .HasConversion<string>()
                .HasMaxLength(20);

            entity.HasMany(o => o.OrderItems)
                .WithOne(oi => oi.Order)
                .HasForeignKey(oi => oi.OrderId)
                // Deleting an order deletes its line items too.
                .OnDelete(DeleteBehavior.Cascade);
        });

        // ---------- OrderItem ----------
        builder.Entity<OrderItem>(entity =>
        {
            entity.Property(oi => oi.UnitPrice)
                .HasPrecision(18, 2);

            entity.HasOne(oi => oi.Product)
                .WithMany()
                .HasForeignKey(oi => oi.ProductId)
                // Prevent deleting a product that has been ordered previously.
                .OnDelete(DeleteBehavior.Restrict);
        });

        // ---------- Seed data ----------
        builder.Entity<Category>().HasData(
            new Category { Id = 1, Name = "Electronics" },
            new Category { Id = 2, Name = "Books" },
            new Category { Id = 3, Name = "Clothing" },
            new Category { Id = 4, Name = "Home" }
        );

        builder.Entity<Product>().HasData(
            new Product { Id = 1, Name = "Wireless Mouse", Description = "Ergonomic 2.4GHz wireless mouse", Price = 19.99m, Stock = 150, CategoryId = 1 },
            new Product { Id = 2, Name = "Mechanical Keyboard", Description = "RGB backlit mechanical keyboard", Price = 59.99m, Stock = 80, CategoryId = 1 },
            new Product { Id = 3, Name = "Clean Code", Description = "A Handbook of Agile Software Craftsmanship", Price = 34.50m, Stock = 40, CategoryId = 2 },
            new Product { Id = 4, Name = "The Pragmatic Programmer", Description = "Your journey to mastery", Price = 39.99m, Stock = 35, CategoryId = 2 },
            new Product { Id = 5, Name = "Men's T-Shirt", Description = "100% cotton crew neck t-shirt", Price = 14.99m, Stock = 200, CategoryId = 3 },
            new Product { Id = 6, Name = "Table Lamp", Description = "LED desk lamp with adjustable brightness", Price = 24.99m, Stock = 60, CategoryId = 4 }
        );
    }
}
