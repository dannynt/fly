using UnityEngine;
using UnityEngine.UIElements;
using UnityEngine.SceneManagement;
using System.Collections.Generic;

[RequireComponent(typeof(UIDocument))]
public class GameHUD : MonoBehaviour
{
    [Header("References (auto-found if empty)")]
    public VehicleHealth playerHealth;
    public WantedLevel wantedLevel;
    public PackageManager packageManager;

    [Tooltip("Drag GameHUD.uss here as fallback if the UXML style link doesn't resolve")]
    public StyleSheet hudStyleSheet;

    [Header("Speedometer")]
    public float maxSpeedKmh = 200f;

    [Header("Minimap")]
    public float minimapHeight = 120f;
    public int minimapResWidth = 440;
    public int minimapResHeight = 300;

    [Header("Responsive Scaling")]
    [Tooltip("Reference resolution the HUD was designed for")]
    public Vector2Int referenceResolution = new Vector2Int(1920, 1080);
    [Range(0f, 1f), Tooltip("0 = match width, 1 = match height, 0.5 = blend")]
    public float matchWidthOrHeight = 0.5f;

    private VisualElement hudRoot;

    // Dashboard elements
    private VisualElement dashboard;
    private VisualElement dashMoney;
    private Label moneyValue;
    private VisualElement dashWanted;
    private Label starText;
    private VisualElement speedoContainer;
    private Label speedValue;
    private VisualElement speedoGlow;
    private VisualElement speedoNeedlePivot;
    private VisualElement speedoTicks;
    private VisualElement dashHealthRow;
    private VisualElement healthBarFill;
    private Label healthText;
    private VisualElement dashHeatRow;
    private VisualElement heatBarFill;

    // Speedometer dial
    private readonly List<VisualElement> tickElements = new();
    private float needleAngle = -135f;
    private float needleVelocity;
    private float displayedSpeed;

    private const float ARC_START_DEG = -135f;
    private const float ARC_SPAN_DEG = 270f;
    private const int TICK_COUNT = 21;
    private const float DIAL_SIZE = 200f;

    // Delivery
    private VisualElement deliveryPanel;
    private Label deliveryTypeLabel;
    private Label deliveryStatusLabel;
    private Label deliveryRewardValue;
    private VisualElement pkgHealthStrip;
    private VisualElement pkgHealthBarFill;
    private Label deliveryTimer;

    // Minimap
    private VisualElement minimapImage;

    // Overlays
    private VisualElement arrestOverlay;
    private Label arrestPenalty;
    private VisualElement deliveryResultOverlay;
    private Label deliveryResultText;
    private VisualElement wreckedOverlay;
    private Button restartBtn;
    private Button repairBtn;

    // Notifications
    private VisualElement notificationContainer;

    // Runtime
    private float displayedHealth;
    private Rigidbody playerRb;
    private Camera minimapCam;
    private RenderTexture minimapRT;
    private float arrestDisplayTimer;
    private float deliveryResultTimer;
    private int lastMoney;
    private int lastStars;
    private float lastSpeedKmh;

    // Juice timers
    private float speedPopTimer;
    private float moneyPopTimer;
    private float starPopTimer;
    private float healthHitTimer;
    private float arrestEnterTimer;
    private float resultEnterTimer;
    private float timerPulseAccum;

    void Start()
    {
        if (playerHealth == null)
        {
            var player = FindAnyObjectByType<FlyingCarController>();
            if (player != null) playerHealth = player.GetComponent<VehicleHealth>();
        }
        if (wantedLevel == null)
            wantedLevel = FindAnyObjectByType<WantedLevel>();
        if (packageManager == null)
            packageManager = FindAnyObjectByType<PackageManager>();

        if (playerHealth != null)
        {
            displayedHealth = playerHealth.CurrentHealth;
            playerRb = playerHealth.GetComponent<Rigidbody>();
        }

        var uiDoc = GetComponent<UIDocument>();
        var root = uiDoc.rootVisualElement;
        if (hudStyleSheet != null)
            root.styleSheets.Add(hudStyleSheet);

        // Configure responsive scaling via PanelSettings
        if (uiDoc.panelSettings != null)
        {
            uiDoc.panelSettings.scaleMode = PanelScaleMode.ScaleWithScreenSize;
            uiDoc.panelSettings.referenceResolution = referenceResolution;
            uiDoc.panelSettings.screenMatchMode = PanelScreenMatchMode.MatchWidthOrHeight;
            uiDoc.panelSettings.match = matchWidthOrHeight;
        }

        hudRoot = root.Q("hud-root");

        // Dashboard
        dashboard = root.Q("dashboard");
        dashMoney = root.Q("dash-money");
        moneyValue = root.Q<Label>("money-value");
        dashWanted = root.Q("dash-wanted");
        starText = root.Q<Label>("star-text");
        speedoContainer = root.Q("speedo-container");
        speedValue = root.Q<Label>("speed-value");
        speedoGlow = root.Q("speedo-glow");
        speedoNeedlePivot = root.Q("speedo-needle-pivot");
        speedoTicks = root.Q("speedo-ticks");
        dashHealthRow = root.Q("dash-health-row");
        healthBarFill = root.Q("health-bar-fill");
        healthText = root.Q<Label>("health-text");
        dashHeatRow = root.Q("dash-heat-row");
        heatBarFill = root.Q("heat-bar-fill");

        SetupSpeedoTicks();

        // Delivery
        deliveryPanel = root.Q("delivery-panel");
        deliveryTypeLabel = root.Q<Label>("delivery-type-label");
        deliveryStatusLabel = root.Q<Label>("delivery-status-label");
        deliveryRewardValue = root.Q<Label>("delivery-reward-value");
        pkgHealthStrip = root.Q("pkg-health-strip");
        pkgHealthBarFill = root.Q("pkg-health-bar-fill");
        deliveryTimer = root.Q<Label>("delivery-timer");

        // Minimap
        minimapImage = root.Q("minimap-image");

        // Overlays
        arrestOverlay = root.Q("arrest-overlay");
        arrestPenalty = root.Q<Label>("arrest-penalty");
        deliveryResultOverlay = root.Q("delivery-result-overlay");
        deliveryResultText = root.Q<Label>("delivery-result-text");
        wreckedOverlay = root.Q("wrecked-overlay");
        restartBtn = root.Q<Button>("restart-btn");
        repairBtn = root.Q<Button>("repair-btn");

        // Notifications
        notificationContainer = root.Q("notification-container");

        // Initial state
        dashHeatRow.style.display = DisplayStyle.None;
        arrestOverlay.style.display = DisplayStyle.None;
        deliveryResultOverlay.style.display = DisplayStyle.None;

        // Buttons
        restartBtn.clicked += OnRestartClicked;
        repairBtn.clicked += OnRepairClicked;

        // Subscribe to game events
        PoliceCarController.OnPlayerArrested += OnArrestDisplay;

        if (packageManager != null)
        {
            packageManager.OnDeliveryComplete += OnDeliveryCompleteDisplay;
            packageManager.OnDeliveryFailed += OnDeliveryFailedDisplay;
            packageManager.OnMissionSpawned += OnMissionSpawned;
        }

        if (wantedLevel != null)
        {
            wantedLevel.OnHeatChanged += OnHeatChanged;
            wantedLevel.OnHeatCleared += OnHeatCleared;
        }

        if (playerHealth != null)
        {
            playerHealth.OnDamaged += OnPlayerDamaged;
            playerHealth.OnDeath += OnPlayerDeath;
            playerHealth.OnRepaired += OnPlayerRepaired;
        }

        if (MoneyManager.Instance != null)
            lastMoney = MoneyManager.Instance.CurrentMoney;

        SetupMinimapCamera();
    }

    void OnDestroy()
    {
        if (restartBtn != null) restartBtn.clicked -= OnRestartClicked;
        if (repairBtn != null) repairBtn.clicked -= OnRepairClicked;
        if (minimapRT != null) minimapRT.Release();
        if (minimapCam != null) Destroy(minimapCam.gameObject);

        PoliceCarController.OnPlayerArrested -= OnArrestDisplay;

        if (packageManager != null)
        {
            packageManager.OnDeliveryComplete -= OnDeliveryCompleteDisplay;
            packageManager.OnDeliveryFailed -= OnDeliveryFailedDisplay;
            packageManager.OnMissionSpawned -= OnMissionSpawned;
        }

        if (wantedLevel != null)
        {
            wantedLevel.OnHeatChanged -= OnHeatChanged;
            wantedLevel.OnHeatCleared -= OnHeatCleared;
        }

        if (playerHealth != null)
        {
            playerHealth.OnDamaged -= OnPlayerDamaged;
            playerHealth.OnDeath -= OnPlayerDeath;
            playerHealth.OnRepaired -= OnPlayerRepaired;
        }
    }

    void Update()
    {
        UpdateSpeed();
        UpdateHealthBar();
        UpdateWantedDisplay();
        UpdateMoney();
        UpdateDeliveryPanel();
        UpdateMinimap();
        UpdateArrestOverlay();
        UpdateDeliveryResultFlash();
        UpdateJuiceTimers();
    }

    // -----------------------------------------------------------
    //  Speedometer Setup & Update
    // -----------------------------------------------------------

    private void SetupSpeedoTicks()
    {
        for (int i = 0; i < TICK_COUNT; i++)
        {
            float t = i / (float)(TICK_COUNT - 1);
            float angleDeg = ARC_START_DEG + t * ARC_SPAN_DEG;
            bool isMajor = (i % 5 == 0);

            // Wrapper at center of dial, rotated to correct angle
            var wrapper = new VisualElement();
            wrapper.style.position = Position.Absolute;
            wrapper.style.left = DIAL_SIZE / 2f;
            wrapper.style.top = DIAL_SIZE / 2f;
            wrapper.style.width = 0;
            wrapper.style.height = 0;
            wrapper.transform.rotation = Quaternion.Euler(0, 0, angleDeg);

            // Tick bar extending outward
            var tick = new VisualElement();
            tick.style.position = Position.Absolute;
            float tickW = isMajor ? 3f : 1.5f;
            float tickH = isMajor ? 16f : 9f;
            tick.style.width = tickW;
            tick.style.height = tickH;
            tick.style.left = -tickW / 2f;
            tick.style.top = -(DIAL_SIZE / 2f - 6f);
            tick.style.backgroundColor = new Color(0.2f, 0.25f, 0.3f);
            tick.style.borderTopLeftRadius = 1;
            tick.style.borderTopRightRadius = 1;

            wrapper.Add(tick);
            speedoTicks.Add(wrapper);
            tickElements.Add(tick);

            // Speed labels at major ticks
            if (isMajor)
            {
                int kmh = i * 10;
                float angleRad = angleDeg * Mathf.Deg2Rad;
                float labelRadius = DIAL_SIZE / 2f - 30f;

                float lx = Mathf.Sin(angleRad) * labelRadius;
                float ly = -Mathf.Cos(angleRad) * labelRadius;

                var label = new Label(kmh.ToString());
                label.style.position = Position.Absolute;
                label.style.left = DIAL_SIZE / 2f + lx - 18f;
                label.style.top = DIAL_SIZE / 2f + ly - 8f;
                label.style.width = 36f;
                label.style.height = 16f;
                label.style.fontSize = 10;
                label.style.color = new Color(0.4f, 0.5f, 0.6f);
                label.style.unityTextAlign = TextAnchor.MiddleCenter;
                label.style.unityFontStyleAndWeight = FontStyle.Bold;
                label.pickingMode = PickingMode.Ignore;

                speedoTicks.Add(label);
            }
        }
    }

    private void UpdateSpeed()
    {
        if (playerRb == null) return;

        float speedKmh = playerRb.linearVelocity.magnitude * 3.6f;
        float pct = Mathf.Clamp01(speedKmh / maxSpeedKmh);

        // Smooth speed display
        displayedSpeed = Mathf.Lerp(displayedSpeed, speedKmh, Time.deltaTime * 12f);
        speedValue.text = Mathf.RoundToInt(displayedSpeed).ToString();

        // Needle rotation with spring-damped smoothing
        float targetAngle = ARC_START_DEG + pct * ARC_SPAN_DEG;
        needleAngle = Mathf.SmoothDamp(needleAngle, targetAngle, ref needleVelocity, 0.12f);
        speedoNeedlePivot.transform.rotation = Quaternion.Euler(0, 0, needleAngle);

        // Color active ticks - illuminate up to current speed
        for (int i = 0; i < tickElements.Count; i++)
        {
            float tickPct = i / (float)(tickElements.Count - 1);
            bool isActive = tickPct <= pct;
            bool isRedzone = i >= 17; // last 4 ticks = 170-200 km/h

            if (isActive)
            {
                Color tickColor;
                if (tickPct < 0.5f)
                    tickColor = Color.Lerp(new Color(0f, 0.82f, 0.96f), new Color(1f, 0.85f, 0.1f), tickPct * 2f);
                else
                    tickColor = Color.Lerp(new Color(1f, 0.85f, 0.1f), new Color(1f, 0.24f, 0.39f), (tickPct - 0.5f) * 2f);
                tickElements[i].style.backgroundColor = tickColor;
            }
            else if (isRedzone)
            {
                tickElements[i].style.backgroundColor = new Color(0.35f, 0.12f, 0.15f);
            }
            else
            {
                tickElements[i].style.backgroundColor = new Color(0.2f, 0.25f, 0.3f);
            }
        }

        // Glow ring - intensifies at high speed
        float glowAlpha = pct > 0.5f ? (pct - 0.5f) / 0.5f * 0.35f : 0f;
        Color glowColor;
        if (pct < 0.6f)
            glowColor = new Color(0f, 0.82f, 0.96f, glowAlpha);
        else
            glowColor = Color.Lerp(new Color(1f, 0.7f, 0.1f, glowAlpha),
                                    new Color(1f, 0.24f, 0.39f, glowAlpha),
                                    (pct - 0.6f) / 0.4f);
        speedoGlow.style.borderTopColor = glowColor;
        speedoGlow.style.borderRightColor = glowColor;
        speedoGlow.style.borderBottomColor = glowColor;
        speedoGlow.style.borderLeftColor = glowColor;

        // Speed value color shift
        Color numColor;
        if (pct < 0.6f)
            numColor = Color.white;
        else if (pct < 0.8f)
            numColor = Color.Lerp(Color.white, new Color(1f, 0.85f, 0.1f), (pct - 0.6f) / 0.2f);
        else
            numColor = Color.Lerp(new Color(1f, 0.85f, 0.1f), new Color(1f, 0.24f, 0.39f), (pct - 0.8f) / 0.2f);
        speedValue.style.color = numColor;

        // Danger state
        bool danger = wantedLevel != null && speedKmh > wantedLevel.speedingThreshold * 3.6f;
        dashboard.EnableInClassList("speed-danger", danger);

        // Speed pop on rapid acceleration
        if (Mathf.Abs(speedKmh - lastSpeedKmh) > 20f)
            speedPopTimer = 0.15f;
        lastSpeedKmh = speedKmh;
    }

    // -----------------------------------------------------------
    //  Health
    // -----------------------------------------------------------

    private void UpdateHealthBar()
    {
        if (playerHealth == null) return;

        float target = playerHealth.CurrentHealth;
        displayedHealth = Mathf.Lerp(displayedHealth, target, Time.deltaTime * 8f);
        float pct = Mathf.Clamp01(displayedHealth / playerHealth.maxHealth);

        healthBarFill.style.width = new Length(pct * 100f, LengthUnit.Percent);

        // Cyan → yellow → magenta
        Color barColor;
        if (pct > 0.5f)
            barColor = Color.Lerp(new Color(1f, 0.85f, 0.1f), new Color(0f, 0.82f, 0.96f), (pct - 0.5f) * 2f);
        else
            barColor = Color.Lerp(new Color(1f, 0.24f, 0.39f), new Color(1f, 0.85f, 0.1f), pct * 2f);
        healthBarFill.style.backgroundColor = barColor;

        healthText.text = Mathf.CeilToInt(playerHealth.CurrentHealth).ToString();

        bool critical = pct < 0.25f && !playerHealth.IsDead;
        dashHealthRow.EnableInClassList("health-critical",
            critical && Mathf.PingPong(Time.time * 3f, 1f) > 0.5f);

        dashboard.EnableInClassList("dashboard-critical", critical);

        if (playerHealth.IsDead)
        {
            wreckedOverlay.style.display = DisplayStyle.Flex;
            if (repairBtn != null)
            {
                bool canAfford = MoneyManager.Instance != null && MoneyManager.Instance.CanAfford(playerHealth.repairCost);
                repairBtn.text = $"REPAIR (${playerHealth.repairCost})";
                repairBtn.SetEnabled(canAfford);
            }
        }
    }

    // -----------------------------------------------------------
    //  Wanted / Heat
    // -----------------------------------------------------------

    private void UpdateWantedDisplay()
    {
        if (wantedLevel == null) return;

        bool wanted = wantedLevel.IsWanted;
        dashHeatRow.style.display = wanted ? DisplayStyle.Flex : DisplayStyle.None;
        dashboard.EnableInClassList("dashboard-wanted", wanted);

        if (!wanted)
        {
            starText.text = "";
            return;
        }

        int stars = wantedLevel.Stars;
        starText.text = new string('\u2605', stars) + new string('\u2606', 5 - stars);

        dashWanted.EnableInClassList("star-flash",
            stars >= 4 && Mathf.PingPong(Time.time * 4f, 1f) > 0.5f);

        float heatPct = Mathf.Clamp01(wantedLevel.CurrentHeat / wantedLevel.maxHeat);
        heatBarFill.style.width = new Length(heatPct * 100f, LengthUnit.Percent);

        Color heatColor = Color.Lerp(new Color(1f, 0.7f, 0.12f), new Color(1f, 0.24f, 0.39f), heatPct);
        heatBarFill.style.backgroundColor = heatColor;
    }

    // -----------------------------------------------------------
    //  Money
    // -----------------------------------------------------------

    private void UpdateMoney()
    {
        if (MoneyManager.Instance == null) return;

        int current = MoneyManager.Instance.CurrentMoney;
        moneyValue.text = current.ToString();

        if (current != lastMoney)
        {
            bool gained = current > lastMoney;
            dashboard.EnableInClassList("money-gain", gained);
            dashboard.EnableInClassList("money-loss", !gained);
            moneyPopTimer = 0.25f;
            lastMoney = current;
        }
    }

    // -----------------------------------------------------------
    //  Delivery
    // -----------------------------------------------------------

    private void UpdateDeliveryPanel()
    {
        if (packageManager == null) return;

        bool show = packageManager.HasActiveDelivery || packageManager.HasPendingPickup;
        deliveryPanel.style.display = show ? DisplayStyle.Flex : DisplayStyle.None;
        if (!show) return;

        deliveryTypeLabel.text = packageManager.GetPackageTypeName();
        deliveryRewardValue.text = packageManager.ActiveReward.ToString();

        deliveryStatusLabel.text = packageManager.HasPendingPickup
            ? "Pick up package"
            : "Deliver to destination";

        // Accent color by package type
        deliveryPanel.RemoveFromClassList("delivery-illegal");
        deliveryPanel.RemoveFromClassList("delivery-fragile");
        deliveryPanel.RemoveFromClassList("delivery-heavy");
        deliveryPanel.RemoveFromClassList("delivery-timed");
        if (packageManager.HasActiveDelivery || packageManager.HasPendingPickup)
        {
            switch (packageManager.ActiveType)
            {
                case PackageManager.PackageType.Illegal: deliveryPanel.AddToClassList("delivery-illegal"); break;
                case PackageManager.PackageType.Fragile: deliveryPanel.AddToClassList("delivery-fragile"); break;
                case PackageManager.PackageType.Heavy: deliveryPanel.AddToClassList("delivery-heavy"); break;
                case PackageManager.PackageType.Timed: deliveryPanel.AddToClassList("delivery-timed"); break;
            }
        }

        // Fragile health bar
        bool isFragile = packageManager.HasActiveDelivery && packageManager.ActiveType == PackageManager.PackageType.Fragile;
        pkgHealthStrip.style.display = isFragile ? DisplayStyle.Flex : DisplayStyle.None;
        if (isFragile)
        {
            float pct = Mathf.Clamp01(packageManager.FragileHealth / packageManager.FragileMaxHealth);
            pkgHealthBarFill.style.width = new Length(pct * 100f, LengthUnit.Percent);

            Color pkgColor = pct > 0.5f
                ? Color.Lerp(new Color(1f, 0.85f, 0.1f), new Color(0f, 0.82f, 0.96f), (pct - 0.5f) * 2f)
                : Color.Lerp(new Color(1f, 0.24f, 0.39f), new Color(1f, 0.85f, 0.1f), pct * 2f);
            pkgHealthBarFill.style.backgroundColor = pkgColor;
        }

        // Timer
        bool isTimed = packageManager.IsTimedDelivery;
        deliveryTimer.style.display = isTimed ? DisplayStyle.Flex : DisplayStyle.None;
        if (isTimed)
        {
            float t = packageManager.TimedRemainingSeconds;
            deliveryTimer.text = t.ToString("F1");
            deliveryPanel.EnableInClassList("timer-urgent", t < 10f);

            timerPulseAccum += Time.deltaTime;
            if (t < 10f)
                deliveryPanel.EnableInClassList("timer-pulse", Mathf.PingPong(timerPulseAccum * 3f, 1f) > 0.5f);
            else
                deliveryPanel.RemoveFromClassList("timer-pulse");
        }
        else
        {
            deliveryPanel.RemoveFromClassList("timer-urgent");
            deliveryPanel.RemoveFromClassList("timer-pulse");
        }
    }

    // -----------------------------------------------------------
    //  Juice timers
    // -----------------------------------------------------------

    private void UpdateJuiceTimers()
    {
        // Speed pop
        if (speedPopTimer > 0f)
        {
            speedPopTimer -= Time.deltaTime;
            speedoContainer.AddToClassList("speed-pop");
        }
        else
        {
            speedoContainer.RemoveFromClassList("speed-pop");
        }

        // Money pop
        if (moneyPopTimer > 0f)
        {
            moneyPopTimer -= Time.deltaTime;
            dashboard.AddToClassList("money-pop");
        }
        else
        {
            dashboard.RemoveFromClassList("money-pop");
            dashboard.RemoveFromClassList("money-gain");
            dashboard.RemoveFromClassList("money-loss");
        }

        // Star pop
        if (starPopTimer > 0f)
        {
            starPopTimer -= Time.deltaTime;
            dashWanted.AddToClassList("star-pop");
        }
        else
        {
            dashWanted.RemoveFromClassList("star-pop");
        }

        // Health hit flash
        if (healthHitTimer > 0f)
        {
            healthHitTimer -= Time.deltaTime;
            dashHealthRow.AddToClassList("health-hit");
        }
        else
        {
            dashHealthRow.RemoveFromClassList("health-hit");
        }

        // Arrest overlay entrance
        if (arrestEnterTimer > 0f)
        {
            arrestEnterTimer -= Time.deltaTime;
            arrestOverlay.AddToClassList("arrest-enter");
        }
        else
        {
            arrestOverlay.RemoveFromClassList("arrest-enter");
        }

        // Result overlay entrance
        if (resultEnterTimer > 0f)
        {
            resultEnterTimer -= Time.deltaTime;
            deliveryResultOverlay.AddToClassList("result-enter");
        }
        else
        {
            deliveryResultOverlay.RemoveFromClassList("result-enter");
        }
    }

    // -----------------------------------------------------------
    //  Notification System
    // -----------------------------------------------------------

    private enum NotifType { Success, Danger, Warning, Info, Police }

    private void ShowNotification(string message, NotifType type)
    {
        var notif = new VisualElement();
        notif.AddToClassList("notification");
        notif.pickingMode = PickingMode.Ignore;

        var accent = new VisualElement();
        accent.AddToClassList("notif-accent");
        accent.AddToClassList("notif-accent-" + type.ToString().ToLowerInvariant());
        notif.Add(accent);

        var label = new Label(message);
        label.AddToClassList("notif-text");
        label.pickingMode = PickingMode.Ignore;
        notif.Add(label);

        notificationContainer.Insert(0, notif);

        // Animate in (next frame so initial style applies first)
        notif.schedule.Execute(() =>
        {
            notif.AddToClassList("notif-visible");
        }).ExecuteLater(30);

        // Animate out
        notif.schedule.Execute(() =>
        {
            notif.RemoveFromClassList("notif-visible");
            notif.AddToClassList("notif-exit");
        }).ExecuteLater(3000);

        // Remove from DOM
        notif.schedule.Execute(() =>
        {
            notif.RemoveFromHierarchy();
        }).ExecuteLater(3500);
    }

    // -----------------------------------------------------------
    //  Event Handlers → Notifications + Overlays
    // -----------------------------------------------------------

    private void OnHeatChanged(float newHeat, int oldStars, int newStars)
    {
        if (newStars > oldStars)
        {
            starPopTimer = 0.3f;
            ShowNotification("WANTED  " + new string('\u2605', newStars), NotifType.Police);
        }
    }

    private void OnHeatCleared()
    {
        ShowNotification("HEAT LOST", NotifType.Success);
    }

    private void OnMissionSpawned()
    {
        ShowNotification("NEW DELIVERY AVAILABLE", NotifType.Info);
    }

    private void OnPlayerDamaged(float damage)
    {
        healthHitTimer = 0.2f;
        if (damage > playerHealth.maxHealth * 0.3f)
            ShowNotification("HEAVY DAMAGE!", NotifType.Warning);
    }

    private void OnPlayerDeath()
    {
        ShowNotification("VEHICLE WRECKED", NotifType.Danger);
    }

    private void OnPlayerRepaired(float newHealth)
    {
        wreckedOverlay.style.display = DisplayStyle.None;
        ShowNotification("REPAIRED", NotifType.Success);
    }

    // -----------------------------------------------------------
    //  Arrest overlay
    // -----------------------------------------------------------

    private void OnArrestDisplay()
    {
        arrestDisplayTimer = 3f;
        arrestEnterTimer = 0.4f;
        if (MoneyManager.Instance != null)
        {
            int penalty = Mathf.RoundToInt(MoneyManager.Instance.CurrentMoney * 0.3f);
            arrestPenalty.text = $"-${penalty}";
        }
        ShowNotification("BUSTED", NotifType.Police);
    }

    private void UpdateArrestOverlay()
    {
        if (arrestDisplayTimer > 0f)
        {
            arrestDisplayTimer -= Time.deltaTime;
            arrestOverlay.style.display = DisplayStyle.Flex;
        }
        else
        {
            arrestOverlay.style.display = DisplayStyle.None;
        }
    }

    // -----------------------------------------------------------
    //  Delivery result flash
    // -----------------------------------------------------------

    private void OnDeliveryCompleteDisplay(int reward)
    {
        deliveryResultTimer = 2.5f;
        resultEnterTimer = 0.4f;
        deliveryResultText.text = $"DELIVERED +${reward}";
        deliveryResultOverlay.EnableInClassList("delivery-success", true);
        deliveryResultOverlay.EnableInClassList("delivery-failed", false);
        ShowNotification($"+${reward} DELIVERY COMPLETE", NotifType.Success);
    }

    private void OnDeliveryFailedDisplay(string reason)
    {
        deliveryResultTimer = 2.5f;
        resultEnterTimer = 0.4f;
        deliveryResultText.text = reason;
        deliveryResultOverlay.EnableInClassList("delivery-success", false);
        deliveryResultOverlay.EnableInClassList("delivery-failed", true);
        ShowNotification("DELIVERY FAILED", NotifType.Danger);
    }

    private void UpdateDeliveryResultFlash()
    {
        if (deliveryResultTimer > 0f)
        {
            deliveryResultTimer -= Time.deltaTime;
            deliveryResultOverlay.style.display = DisplayStyle.Flex;
        }
        else
        {
            deliveryResultOverlay.style.display = DisplayStyle.None;
        }
    }

    // -----------------------------------------------------------
    //  Minimap
    // -----------------------------------------------------------

    private void SetupMinimapCamera()
    {
        minimapRT = new RenderTexture(minimapResWidth, minimapResHeight, 16);
        minimapRT.Create();

        var camGO = new GameObject("MinimapCamera");
        minimapCam = camGO.AddComponent<Camera>();
        minimapCam.orthographic = true;
        minimapCam.orthographicSize = minimapHeight;
        minimapCam.clearFlags = CameraClearFlags.SolidColor;
        minimapCam.backgroundColor = new Color(0.02f, 0.05f, 0.08f, 1f);
        minimapCam.cullingMask = ~0;
        minimapCam.targetTexture = minimapRT;
        minimapCam.depth = -10;

        minimapImage.style.backgroundImage = Background.FromRenderTexture(minimapRT);
    }

    private void UpdateMinimap()
    {
        if (minimapCam == null || playerRb == null) return;

        Vector3 pos = playerRb.position + Vector3.up * 200f;
        minimapCam.transform.position = pos;
        minimapCam.transform.rotation = Quaternion.Euler(90f, playerRb.transform.eulerAngles.y, 0f);
    }

    // -----------------------------------------------------------
    //  Restart / Repair
    // -----------------------------------------------------------

    private void OnRepairClicked()
    {
        if (playerHealth != null && playerHealth.TryRepair())
        {
            wreckedOverlay.style.display = DisplayStyle.None;
        }
    }

    private void OnRestartClicked()
    {
        Time.timeScale = 1f;
        SceneManager.LoadScene(SceneManager.GetActiveScene().buildIndex);
    }
}
