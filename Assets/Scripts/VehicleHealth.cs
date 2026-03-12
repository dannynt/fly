using UnityEngine;
using System;

public class VehicleHealth : MonoBehaviour
{
    [Header("Health")]
    [Tooltip("Maximum hit points for this vehicle")]
    public float maxHealth = 100f;

    [Header("Collision Damage")]
    [Tooltip("Impacts below this force are ignored (prevents tiny bumps from doing damage)")]
    public float minImpactForce = 5f;
    [Tooltip("Damage multiplier applied to impact force above the minimum threshold")]
    public float damageMultiplier = 1f;
    [Tooltip("Minimum seconds between taking collision damage (prevents many hits in one frame)")]
    public float damageCooldown = 0.3f;
    [Tooltip("If true, this vehicle only takes collision damage from the player")]
    public bool onlyPlayerDamage = false;

    [Header("Death Effects")]
    [Tooltip("How much angular tumble to apply when the vehicle dies")]
    public float deathTumbleForce = 50f;

    /// <summary>Current health. When it reaches 0 the vehicle is dead.</summary>
    public float CurrentHealth { get; private set; }

    /// <summary>True once health has reached zero.</summary>
    public bool IsDead { get; private set; }

    /// <summary>Fires when damage is taken. Arg = damage amount.</summary>
    public event Action<float> OnDamaged;

    /// <summary>Fires once when the vehicle dies.</summary>
    public event Action OnDeath;

    /// <summary>Fires when the vehicle is repaired. Arg = new health.</summary>
    public event Action<float> OnRepaired;

    [Header("Repair")]
    [Tooltip("Cost to fully repair this vehicle")]
    public int repairCost = 200;

    private float lastDamageTime = -999f;
    private Rigidbody rb;

    void Awake()
    {
        CurrentHealth = maxHealth;
        rb = GetComponent<Rigidbody>();
    }

    /// <summary>Apply a specific amount of damage. Triggers death at 0.</summary>
    public void TakeDamage(float amount)
    {
        if (IsDead || amount <= 0f) return;

        CurrentHealth = Mathf.Max(CurrentHealth - amount, 0f);
        OnDamaged?.Invoke(amount);

        if (CurrentHealth <= 0f)
            Die();
    }

    private void Die()
    {
        if (IsDead) return;
        IsDead = true;

        // Add a small random tumble so the wreck looks dramatic
        if (rb != null)
        {
            Vector3 randomTorque = UnityEngine.Random.insideUnitSphere * deathTumbleForce;
            rb.AddTorque(randomTorque, ForceMode.VelocityChange);
        }

        OnDeath?.Invoke();
    }

    /// <summary>Repair the vehicle to full health if the player can afford it. Returns true on success.</summary>
    public bool TryRepair()
    {
        if (!IsDead) return false;
        if (MoneyManager.Instance == null || !MoneyManager.Instance.CanAfford(repairCost))
            return false;

        MoneyManager.Instance.ChangeMoney(-repairCost);
        CurrentHealth = maxHealth;
        IsDead = false;

        // Stabilize physics
        if (rb != null)
        {
            rb.linearVelocity = Vector3.zero;
            rb.angularVelocity = Vector3.zero;
        }

        OnRepaired?.Invoke(CurrentHealth);
        return true;
    }

    private void OnCollisionEnter(Collision collision)
    {
        if (IsDead) return;
        if (Time.time - lastDamageTime < damageCooldown) return;

        // If restricted to player damage, check if the other object is the player
        if (onlyPlayerDamage)
        {
            if (collision.gameObject.GetComponentInParent<FlyingCarController>() == null)
                return;
        }

        float impactForce = collision.impulse.magnitude / Time.fixedDeltaTime;
        // Normalize by mass so lighter and heavier vehicles feel consistent
        if (rb != null) impactForce /= rb.mass;

        if (impactForce < minImpactForce) return;

        float damage = (impactForce - minImpactForce) * damageMultiplier;
        lastDamageTime = Time.time;
        TakeDamage(damage);

        // Also damage the other vehicle if it has health
        var otherHealth = collision.gameObject.GetComponentInParent<VehicleHealth>();
        if (otherHealth != null && !otherHealth.IsDead)
        {
            float otherDamage = damage * 0.5f; // reduced reciprocal damage
            otherHealth.TakeDamage(otherDamage);
        }
    }
}
