using UnityEngine;
using System;

/// <summary>
/// A delivery zone marker. Can be a pickup or dropoff point.
/// Uses a trigger collider to detect the player entering.
/// </summary>
[RequireComponent(typeof(SphereCollider))]
public class DeliveryZone : MonoBehaviour
{
    public enum ZoneType { Pickup, ClientDropoff, DangerZoneDropoff }

    [Header("Zone Settings")]
    public ZoneType zoneType = ZoneType.Pickup;
    public float radius = 8f;

    [Header("Visual")]
    public Color gizmoColor = Color.yellow;

    /// <summary>Fires when the player enters this zone.</summary>
    public event Action<DeliveryZone> OnPlayerEntered;

    private SphereCollider trigger;

    void Awake()
    {
        trigger = GetComponent<SphereCollider>();
        trigger.isTrigger = true;
        trigger.radius = radius;
    }

    private void OnTriggerEnter(Collider other)
    {
        if (other.GetComponentInParent<FlyingCarController>() != null)
        {
            OnPlayerEntered?.Invoke(this);
        }
    }

    private void OnDrawGizmos()
    {
        Gizmos.color = gizmoColor;
        Gizmos.DrawWireSphere(transform.position, radius);
    }
}
