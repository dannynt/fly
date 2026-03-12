using UnityEngine;
using System;

/// <summary>
/// Manages the full delivery loop: spawning missions, tracking active deliveries,
/// applying package modifiers to the player car, and rewarding on completion.
/// Attach to any persistent GameObject (e.g. GameManager).
/// </summary>
public class PackageManager : MonoBehaviour
{
    public enum PackageType { Normal, Fragile, Illegal, Heavy, Timed }

    [Serializable]
    public class PackageTypeWeights
    {
        public PackageType type;
        [Range(0f, 1f)] public float weight = 0.2f;
    }

    // ------------------------------------------------------------------ //
    //  Inspector
    // ------------------------------------------------------------------ //

    [Header("References (auto-found if empty)")]
    public FlyingCarController playerCar;
    public WantedLevel wantedLevel;

    [Header("Zone Spawning")]
    [Tooltip("How far from the player to place pickup/dropoff zones")]
    public float zoneSpawnRadius = 80f;
    [Tooltip("Minimum distance between pickup and dropoff")]
    public float minDeliveryDistance = 40f;
    [Tooltip("Height above ground for zone markers")]
    public float zoneHeight = 6f;

    [Header("Rewards")]
    public int baseReward = 100;
    public int fragileBonus = 80;
    public int illegalBonus = 150;
    public int heavyBonus = 60;
    public int timedBonusPerSecLeft = 10;

    [Header("Timed Delivery")]
    public float timedDeliveryDuration = 45f;

    [Header("Heavy Cargo")]
    [Tooltip("Speed multiplier applied when carrying heavy cargo")]
    public float heavySpeedMultiplier = 0.55f;
    [Tooltip("Extra mass added to the rigidbody for heavy cargo")]
    public float heavyExtraMass = 600f;

    [Header("Fragile Package")]
    [Tooltip("Max package health for fragile deliveries")]
    public float fragileMaxHealth = 100f;
    [Tooltip("Angular velocity threshold that damages fragile packages (sharp turns)")]
    public float fragileAngularThreshold = 2.5f;
    [Tooltip("Linear acceleration threshold that damages fragile packages (boosts/brakes)")]
    public float fragileAccelThreshold = 18f;
    [Tooltip("Damage per second while exceeding thresholds")]
    public float fragileDamageRate = 25f;

    [Header("Illegal Package")]
    [Tooltip("Heat added when picking up an illegal package")]
    public float illegalHeatOnPickup = 25f;

    [Header("Package Type Distribution")]
    public PackageTypeWeights[] typeWeights = new PackageTypeWeights[]
    {
        new PackageTypeWeights { type = PackageType.Normal, weight = 0.3f },
        new PackageTypeWeights { type = PackageType.Fragile, weight = 0.2f },
        new PackageTypeWeights { type = PackageType.Illegal, weight = 0.15f },
        new PackageTypeWeights { type = PackageType.Heavy, weight = 0.15f },
        new PackageTypeWeights { type = PackageType.Timed, weight = 0.2f },
    };

    // ------------------------------------------------------------------ //
    //  Runtime State
    // ------------------------------------------------------------------ //

    /// <summary>True when the player is carrying a package.</summary>
    public bool HasActiveDelivery { get; private set; }
    public PackageType ActiveType { get; private set; }
    public int ActiveReward { get; private set; }

    // Fragile
    public float FragileHealth { get; private set; }
    public float FragileMaxHealth => fragileMaxHealth;

    // Timed
    public float TimedRemainingSeconds { get; private set; }
    public bool IsTimedDelivery => HasActiveDelivery && ActiveType == PackageType.Timed;

    /// <summary>True when waiting at a pickup zone for the player.</summary>
    public bool HasPendingPickup { get; private set; }

    /// <summary>Fires on delivery complete. Arg = reward earned.</summary>
    public event Action<int> OnDeliveryComplete;
    /// <summary>Fires on delivery failed (fragile broke, timer ran out).</summary>
    public event Action<string> OnDeliveryFailed;
    /// <summary>Fires when a new mission is offered.</summary>
    public event Action OnMissionSpawned;

    // Internal
    private DeliveryZone pickupZone;
    private DeliveryZone dropoffZone;
    private Rigidbody playerRb;
    private float originalMaxSpeed;
    private float originalMass;
    private Vector3 lastVelocity;
    private float missionCooldown;

    // ------------------------------------------------------------------ //
    //  Lifecycle
    // ------------------------------------------------------------------ //

    void Start()
    {
        if (playerCar == null)
            playerCar = FindAnyObjectByType<FlyingCarController>();
        if (wantedLevel == null)
            wantedLevel = FindAnyObjectByType<WantedLevel>();

        if (playerCar != null)
        {
            playerRb = playerCar.GetComponent<Rigidbody>();
            originalMaxSpeed = playerCar.maxForwardSpeed;
            originalMass = playerRb.mass;
        }

        // Spawn first mission after a short delay
        missionCooldown = 3f;
    }

    void Update()
    {
        if (playerCar == null) return;

        // Cooldown between missions
        if (!HasActiveDelivery && !HasPendingPickup)
        {
            missionCooldown -= Time.deltaTime;
            if (missionCooldown <= 0f)
                SpawnMission();
        }

        // Active delivery updates
        if (HasActiveDelivery)
        {
            UpdateFragilePackage();
            UpdateTimedDelivery();
        }

        lastVelocity = playerRb != null ? playerRb.linearVelocity : Vector3.zero;
    }

    // ------------------------------------------------------------------ //
    //  Mission Spawning
    // ------------------------------------------------------------------ //

    private void SpawnMission()
    {
        PackageType type = RollPackageType();
        int reward = CalculateReward(type);

        // Find spawn positions around the player
        Vector3 playerPos = playerCar.transform.position;
        Vector3 pickupPos = GetRandomPositionAround(playerPos, zoneSpawnRadius * 0.4f, zoneSpawnRadius * 0.7f);
        Vector3 dropoffPos = GetRandomPositionAround(pickupPos, minDeliveryDistance, zoneSpawnRadius);

        // Create pickup zone
        pickupZone = CreateZone("PickupZone", pickupPos, DeliveryZone.ZoneType.Pickup, new Color(0f, 0.9f, 1f, 0.8f));
        pickupZone.OnPlayerEntered += OnPickup;

        ActiveType = type;
        ActiveReward = reward;
        HasPendingPickup = true;

        // Store dropoff position for later
        dropoffPos.y = zoneHeight;
        pickupZone.gameObject.AddComponent<DropoffData>().dropoffPosition = dropoffPos;

        OnMissionSpawned?.Invoke();
    }

    private void OnPickup(DeliveryZone zone)
    {
        if (!HasPendingPickup) return;

        HasPendingPickup = false;
        HasActiveDelivery = true;

        // Retrieve dropoff position
        Vector3 dropoffPos = zone.GetComponent<DropoffData>().dropoffPosition;

        // Destroy pickup zone
        zone.OnPlayerEntered -= OnPickup;
        Destroy(zone.gameObject);
        pickupZone = null;

        // Create dropoff zone
        Color dropColor = ActiveType == PackageType.Illegal
            ? new Color(1f, 0.2f, 0.3f, 0.8f)
            : new Color(0f, 1f, 0.4f, 0.8f);
        dropoffZone = CreateZone("DropoffZone", dropoffPos, DeliveryZone.ZoneType.ClientDropoff, dropColor);
        dropoffZone.OnPlayerEntered += OnDropoff;

        // Apply package modifiers
        ApplyPackageModifiers();
    }

    private void OnDropoff(DeliveryZone zone)
    {
        if (!HasActiveDelivery) return;

        int reward = ActiveReward;

        // Timed bonus
        if (ActiveType == PackageType.Timed && TimedRemainingSeconds > 0f)
            reward += Mathf.RoundToInt(TimedRemainingSeconds * timedBonusPerSecLeft);

        // Fragile penalty — partial reward based on remaining health
        if (ActiveType == PackageType.Fragile)
            reward = Mathf.RoundToInt(reward * (FragileHealth / fragileMaxHealth));

        CompleteDelivery(reward);
    }

    private void CompleteDelivery(int reward)
    {
        // Pay the player
        if (MoneyManager.Instance != null)
            MoneyManager.Instance.ChangeMoney(reward);

        // Clean up
        RemovePackageModifiers();
        CleanupZones();
        HasActiveDelivery = false;

        OnDeliveryComplete?.Invoke(reward);

        // Queue next mission
        missionCooldown = 4f;
    }

    public void FailDelivery(string reason)
    {
        RemovePackageModifiers();
        CleanupZones();
        HasActiveDelivery = false;
        HasPendingPickup = false;

        OnDeliveryFailed?.Invoke(reason);

        // Queue next mission
        missionCooldown = 5f;
    }

    // ------------------------------------------------------------------ //
    //  Package Modifiers
    // ------------------------------------------------------------------ //

    private void ApplyPackageModifiers()
    {
        switch (ActiveType)
        {
            case PackageType.Heavy:
                playerCar.maxForwardSpeed = originalMaxSpeed * heavySpeedMultiplier;
                if (playerRb != null) playerRb.mass = originalMass + heavyExtraMass;
                break;

            case PackageType.Fragile:
                FragileHealth = fragileMaxHealth;
                break;

            case PackageType.Timed:
                TimedRemainingSeconds = timedDeliveryDuration;
                break;

            case PackageType.Illegal:
                if (wantedLevel != null)
                    wantedLevel.AddHeat(illegalHeatOnPickup);
                break;
        }
    }

    private void RemovePackageModifiers()
    {
        // Restore heavy cargo changes
        if (playerCar != null)
            playerCar.maxForwardSpeed = originalMaxSpeed;
        if (playerRb != null)
            playerRb.mass = originalMass;
    }

    // ------------------------------------------------------------------ //
    //  Fragile Package Update
    // ------------------------------------------------------------------ //

    private void UpdateFragilePackage()
    {
        if (ActiveType != PackageType.Fragile) return;
        if (playerRb == null) return;

        float damage = 0f;

        // Sharp turns damage the package
        float angularSpeed = playerRb.angularVelocity.magnitude;
        if (angularSpeed > fragileAngularThreshold)
            damage += (angularSpeed - fragileAngularThreshold) * fragileDamageRate * Time.deltaTime;

        // Sudden acceleration/deceleration damages the package
        Vector3 accel = (playerRb.linearVelocity - lastVelocity) / Time.deltaTime;
        float accelMag = accel.magnitude;
        if (accelMag > fragileAccelThreshold)
            damage += (accelMag - fragileAccelThreshold) * fragileDamageRate * 0.5f * Time.deltaTime;

        if (damage > 0f)
        {
            FragileHealth = Mathf.Max(FragileHealth - damage, 0f);
            if (FragileHealth <= 0f)
                FailDelivery("PACKAGE DESTROYED");
        }
    }

    // ------------------------------------------------------------------ //
    //  Timed Delivery Update
    // ------------------------------------------------------------------ //

    private void UpdateTimedDelivery()
    {
        if (ActiveType != PackageType.Timed) return;

        TimedRemainingSeconds -= Time.deltaTime;
        if (TimedRemainingSeconds <= 0f)
        {
            TimedRemainingSeconds = 0f;
            FailDelivery("TIME'S UP");
        }
    }

    // ------------------------------------------------------------------ //
    //  Helpers
    // ------------------------------------------------------------------ //

    private PackageType RollPackageType()
    {
        float total = 0f;
        foreach (var w in typeWeights) total += w.weight;

        float roll = UnityEngine.Random.Range(0f, total);
        float acc = 0f;
        foreach (var w in typeWeights)
        {
            acc += w.weight;
            if (roll <= acc) return w.type;
        }
        return PackageType.Normal;
    }

    private int CalculateReward(PackageType type)
    {
        int reward = baseReward;
        switch (type)
        {
            case PackageType.Fragile: reward += fragileBonus; break;
            case PackageType.Illegal: reward += illegalBonus; break;
            case PackageType.Heavy: reward += heavyBonus; break;
            case PackageType.Timed: reward += baseReward; break; // timed bonus applied on delivery
        }
        return reward;
    }

    private Vector3 GetRandomPositionAround(Vector3 center, float minDist, float maxDist)
    {
        Vector2 circle = UnityEngine.Random.insideUnitCircle.normalized * UnityEngine.Random.Range(minDist, maxDist);
        Vector3 pos = center + new Vector3(circle.x, 0f, circle.y);
        pos.y = zoneHeight;
        return pos;
    }

    private DeliveryZone CreateZone(string name, Vector3 position, DeliveryZone.ZoneType type, Color color)
    {
        var go = new GameObject(name);
        go.transform.position = position;
        go.layer = 0; // Default layer
        var zone = go.AddComponent<DeliveryZone>();
        zone.zoneType = type;
        zone.gizmoColor = color;
        zone.radius = 10f;

        // Add a visible marker (simple scaled cube)
        var marker = GameObject.CreatePrimitive(PrimitiveType.Cylinder);
        marker.transform.SetParent(go.transform);
        marker.transform.localPosition = Vector3.zero;
        marker.transform.localScale = new Vector3(16f, 0.3f, 16f);

        // Remove collider from the visual marker (the DeliveryZone's sphere collider handles detection)
        var markerCol = marker.GetComponent<Collider>();
        if (markerCol != null) Destroy(markerCol);

        var rend = marker.GetComponent<Renderer>();
        if (rend != null)
        {
            rend.material = new Material(Shader.Find("Universal Render Pipeline/Lit"));
            rend.material.color = color;
            // Make it emissive and transparent
            rend.material.SetFloat("_Surface", 1f); // Transparent
            rend.material.SetFloat("_Blend", 0f);
            rend.material.SetColor("_EmissionColor", color * 2f);
            rend.material.EnableKeyword("_EMISSION");
            rend.material.renderQueue = 3000;
        }

        return zone;
    }

    private void CleanupZones()
    {
        if (pickupZone != null)
        {
            pickupZone.OnPlayerEntered -= OnPickup;
            Destroy(pickupZone.gameObject);
            pickupZone = null;
        }
        if (dropoffZone != null)
        {
            dropoffZone.OnPlayerEntered -= OnDropoff;
            Destroy(dropoffZone.gameObject);
            dropoffZone = null;
        }
    }

    /// <summary>Get readable name for the active package type.</summary>
    public string GetPackageTypeName()
    {
        switch (ActiveType)
        {
            case PackageType.Fragile: return "FRAGILE";
            case PackageType.Illegal: return "ILLEGAL";
            case PackageType.Heavy: return "HEAVY";
            case PackageType.Timed: return "TIMED";
            default: return "STANDARD";
        }
    }
}

/// <summary>Simple data holder to pass dropoff position from pickup to delivery.</summary>
public class DropoffData : MonoBehaviour
{
    [HideInInspector] public Vector3 dropoffPosition;
}
