using System.Security.Claims;
using ECommerce.Api.Data;
using ECommerce.Api.DTOs;
using ECommerce.Api.Models;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;

namespace ECommerce.Api.Controllers;

[ApiController]
[Route("api/[controller]")]
[Authorize]
public class OrdersController : ControllerBase
{
    private readonly AppDbContext _context;

    public OrdersController(AppDbContext context)
    {
        _context = context;
    }

    [HttpGet("mine")]
    public async Task<ActionResult<List<OrderDto>>> GetMine(CancellationToken cancellationToken)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized();
        }

        var orders = await _context.Orders
            .AsNoTracking()
            .Where(o => o.UserId == userId)
            .Include(o => o.OrderItems)
                .ThenInclude(oi => oi.Product)
            .OrderByDescending(o => o.OrderDate)
            .ToListAsync(cancellationToken);

        var result = orders.Select(MapToDto).ToList();

        return Ok(result);
    }

    [HttpPost]
    public async Task<ActionResult<OrderDto>> Create(CreateOrderDto dto, CancellationToken cancellationToken)
    {
        var userId = User.FindFirstValue(ClaimTypes.NameIdentifier);
        if (string.IsNullOrEmpty(userId))
        {
            return Unauthorized();
        }

        if (dto.Items is null || dto.Items.Count == 0)
        {
            return BadRequest("An order must contain at least one item.");
        }

        var productIds = dto.Items.Select(i => i.ProductId).ToList();
        var products = await _context.Products
            .Where(p => productIds.Contains(p.Id))
            .ToListAsync(cancellationToken);

        var order = new Order
        {
            UserId = userId,
            OrderDate = DateTime.UtcNow,
            Status = OrderStatus.Pending,
            OrderItems = new List<OrderItem>()
        };

        decimal total = 0m;

        foreach (var item in dto.Items)
        {
            var product = products.FirstOrDefault(p => p.Id == item.ProductId);
            if (product is null)
            {
                return BadRequest($"Product {item.ProductId} not found.");
            }

            if (item.Quantity <= 0)
            {
                return BadRequest($"Quantity for product {item.ProductId} must be greater than zero.");
            }

            if (product.Stock < item.Quantity)
            {
                return BadRequest($"Insufficient stock for product '{product.Name}'.");
            }

            // Capture the price at time of purchase, then decrement stock.
            var unitPrice = product.Price;
            product.Stock -= item.Quantity;

            order.OrderItems.Add(new OrderItem
            {
                ProductId = product.Id,
                Quantity = item.Quantity,
                UnitPrice = unitPrice
            });

            total += unitPrice * item.Quantity;
        }

        order.TotalAmount = total;

        _context.Orders.Add(order);
        await _context.SaveChangesAsync(cancellationToken);

        // Reload with navigation properties populated for the response DTO.
        var created = await _context.Orders
            .AsNoTracking()
            .Include(o => o.OrderItems)
                .ThenInclude(oi => oi.Product)
            .FirstAsync(o => o.Id == order.Id, cancellationToken);

        var result = MapToDto(created);

        return CreatedAtAction(nameof(GetMine), null, result);
    }

    private static OrderDto MapToDto(Order order)
    {
        var items = order.OrderItems.Select(oi => new OrderItemDto(
            oi.ProductId,
            oi.Product.Name,
            oi.Quantity,
            oi.UnitPrice,
            oi.UnitPrice * oi.Quantity)).ToList();

        return new OrderDto(order.Id, order.OrderDate, order.Status, order.TotalAmount, items);
    }
}
