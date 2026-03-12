using UnityEngine;
using System;

/// <summary>
/// GTA-style wanted/heat system. Heat rises from crashes and speeding.
/// When heat > 0 police will chase. If the player hides long enough, heat decays.
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class WantedLevel : MonoBehaviour
{
    [Header("Heat Settings")]
    [Tooltip("Maximum heat value (acts like GTA star cap)")]
    public float maxHeat = 100f;

    [Header("Heat Gain — Crashing")]
    [Tooltip("Heat added per collision (scaled by impact force)")]
    public float crashHeatMultiplier = 0.5f;
    [Tooltip("Minimum collision impulse to count as a crash")]
    public float minCrashImpulse = 5f;

    [Header("Heat Gain — Speeding")]
    [Tooltip("Speed above which the player starts gaining heat")]
    public float speedingThreshold = 28f;
    [Tooltip("Heat gained per second while speeding (scaled by excess speed)")]
    public float speedingHeatRate = 2f;

    [Header("Heat Decay — Hiding")]
    [Tooltip("Player must be below this speed to be considered 'hiding'")]
    public float hideSpeedThreshold = 5f;
    [Tooltip("Seconds the player must stay hidden before heat starts decaying")]
    public float hideGracePeriod = 5f;
    [Tooltip("Heat lost per second while hidden (after grace period)")]
    public float heatDecayRate = 8f;

    [Header("Detection")]
    [Tooltip("If any police car is within this range, the player is NOT hidden")]
    public float policeDetectionRadius = 40f;

    /// <summary>Current heat level (0 = clean, maxHeat = max wanted).</summary>
    public float CurrentHeat { get; private set; }

    /// <summary>0–5 star equivalent (each star = maxHeat/5).</summary>
    public int Stars => Mathf.CeilToInt(Mathf.Clamp01(CurrentHeat / maxHeat) * 5f);

    /// <summary>True when the player has any heat at all.</summary>
    public bool IsWanted => CurrentHeat > 0f;

    /// <summary>Fires when heat changes. Args: newHeat, oldStars, newStars.</summary>
    public event Action<float, int, int> OnHeatChanged;

    /// <summary>Fires when heat drops to exactly 0 (player escaped).</summary>
    public event Action OnHeatCleared;

    private Rigidbody rb;
    private float hiddenTimer;

    void Start()
    {
        rb = GetComponent<Rigidbody>();
    }

    void Update()
    {
        if (CurrentHeat <= 0f) return;

        float speed = rb.linearVelocity.magnitude;
        bool isHiding = speed < hideSpeedThreshold && !IsPoliceNearby();

        if (isHiding)
        {
            hiddenTimer += Time.deltaTime;
            if (hiddenTimer >= hideGracePeriod)
            {
                AddHeat(-heatDecayRate * Time.deltaTime);
            }
        }
        else
        {
            hiddenTimer = 0f;
        }

        // Speeding generates heat
        if (speed > speedingThreshold)
        {
            float excess = speed - speedingThreshold;
            AddHeat(excess * speedingHeatRate * Time.deltaTime);
        }
    }

    /// <summary>Add (or subtract) heat. Clamps to [0, maxHeat].</summary>
    public void AddHeat(float amount)
    {
        int oldStars = Stars;
        CurrentHeat = Mathf.Clamp(CurrentHeat + amount, 0f, maxHeat);
        int newStars = Stars;

        if (Mathf.Abs(amount) > 0.001f)
            OnHeatChanged?.Invoke(CurrentHeat, oldStars, newStars);

        if (CurrentHeat <= 0f && oldStars > 0)
            OnHeatCleared?.Invoke();
    }

    private bool IsPoliceNearby()
    {
        // Check all active police cars
        var policeCars = FindObjectsByType<PoliceCarController>(FindObjectsSortMode.None);
        foreach (var pc in policeCars)
        {
            if (pc == null || !pc.gameObject.activeInHierarchy) continue;
            float dist = Vector3.Distance(transform.position, pc.transform.position);
            if (dist < policeDetectionRadius)
                return true;
        }
        return false;
    }

    private void OnCollisionEnter(Collision collision)
    {
        float impactForce = collision.impulse.magnitude / Time.fixedDeltaTime;
        if (rb != null) impactForce /= rb.mass;

        if (impactForce < minCrashImpulse) return;

        float heatGain = (impactForce - minCrashImpulse) * crashHeatMultiplier;
        AddHeat(heatGain);
        hiddenTimer = 0f; // reset hiding on crash
    }
}
