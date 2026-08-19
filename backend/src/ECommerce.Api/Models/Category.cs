namespace ECommerce.Api.Models;

public class Category
{
    public int Id { get; set; }

    public string Name { get; set; } = string.Empty;

    // Navigation property: one category has many products.
    public ICollection<Product> Products { get; set; } = new List<Product>();
}
