namespace ECommerce.Api.Models;

public class OrderItem
{
    public int Id { get; set; }

    public int OrderId { get; set; }

    public Order Order { get; set; } = null!;

    public int ProductId { get; set; }

    public Product Product { get; set; } = null!;

    public int Quantity { get; set; }

    // Price captured at the time of purchase - intentionally decoupled from
    // Product.Price so historical orders remain accurate if prices change later.
    public decimal UnitPrice { get; set; }
}
