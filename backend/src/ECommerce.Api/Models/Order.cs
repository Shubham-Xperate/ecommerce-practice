namespace ECommerce.Api.Models;

public class Order
{
    public int Id { get; set; }

    // FK to ApplicationUser.Id (string, matches IdentityUser primary key type).
    public string UserId { get; set; } = string.Empty;

    public DateTime OrderDate { get; set; }

    public OrderStatus Status { get; set; } = OrderStatus.Pending;

    public decimal TotalAmount { get; set; }

    // Navigation property: one order has many order items.
    public ICollection<OrderItem> OrderItems { get; set; } = new List<OrderItem>();
}
