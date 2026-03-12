using UnityEngine;
using UnityEngine.UIElements;
using UnityEngine.SceneManagement;

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

    // UI elements
    private VisualElement speedPanel;
    private Label speedValue;
    private VisualElement speedBarFill;

    private VisualElement healthStrip;
    private VisualElement healthBarContainer;
    private VisualElement healthBarFill;
    private Label healthText;

    private VisualElement wantedPanel;
    private VisualElement starRow;
    private Label starText;
    private VisualElement heatBarFill;

    private VisualElement minimapImage;
    private VisualElement wreckedOverlay;
    private Button restartBtn;
    private Button repairBtn;

    // Money UI
    private VisualElement moneyPanel;
    private Label moneyValue;

    // Delivery UI
    private VisualElement deliveryPanel;
    private Label deliveryTypeLabel;
    private Label deliveryStatusLabel;
    private Label deliveryRewardValue;
    private VisualElement pkgHealthStrip;
    private VisualElement pkgHealthBarFill;
    private Label deliveryTimer;

    // Arrest UI
    private VisualElement arrestOverlay;
    private Label arrestPenalty;

    // Delivery result flash
    private VisualElement deliveryResultOverlay;
    private Label deliveryResultText;

    // Runtime
    private float displayedHealth;
    private Rigidbody playerRb;
    private Camera minimapCam;
    private RenderTexture minimapRT;
    private float arrestDisplayTimer;
    private float deliveryResultTimer;
    private int lastMoney;

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

        var root = GetComponent<UIDocument>().rootVisualElement;
        if (hudStyleSheet != null)
            root.styleSheets.Add(hudStyleSheet);

        // Query elements
        speedPanel = root.Q("speed-panel");
        speedValue = root.Q<Label>("speed-value");
        speedBarFill = root.Q("speed-bar-fill");

        healthStrip = root.Q("health-strip");
        healthBarContainer = root.Q("health-bar-container");
        healthBarFill = root.Q("health-bar-fill");
        healthText = root.Q<Label>("health-text");

        wantedPanel = root.Q("wanted-panel");
        starRow = root.Q("star-row");
        starText = root.Q<Label>("star-text");
        heatBarFill = root.Q("heat-bar-fill");

        minimapImage = root.Q("minimap-image");
        wreckedOverlay = root.Q("wrecked-overlay");
        restartBtn = root.Q<Button>("restart-btn");
        repairBtn = root.Q<Button>("repair-btn");

        // Money
        moneyPanel = root.Q("money-panel");
        moneyValue = root.Q<Label>("money-value");

        // Delivery
        deliveryPanel = root.Q("delivery-panel");
        deliveryTypeLabel = root.Q<Label>("delivery-type-label");
        deliveryStatusLabel = root.Q<Label>("delivery-status-label");
        deliveryRewardValue = root.Q<Label>("delivery-reward-value");
        pkgHealthStrip = root.Q("pkg-health-strip");
        pkgHealthBarFill = root.Q("pkg-health-bar-fill");
        deliveryTimer = root.Q<Label>("delivery-timer");

        // Arrest
        arrestOverlay = root.Q("arrest-overlay");
        arrestPenalty = root.Q<Label>("arrest-penalty");

        // Delivery result
        deliveryResultOverlay = root.Q("delivery-result-overlay");
        deliveryResultText = root.Q<Label>("delivery-result-text");

        wantedPanel.style.display = DisplayStyle.None;
        arrestOverlay.style.display = DisplayStyle.None;
        deliveryResultOverlay.style.display = DisplayStyle.None;

        restartBtn.clicked += OnRestartClicked;
        repairBtn.clicked += OnRepairClicked;

        // Subscribe to events
        PoliceCarController.OnPlayerArrested += OnArrestDisplay;

        if (packageManager != null)
        {
            packageManager.OnDeliveryComplete += OnDeliveryCompleteDisplay;
            packageManager.OnDeliveryFailed += OnDeliveryFailedDisplay;
        }

        if (MoneyManager.Instance != null)
            lastMoney = MoneyManager.Instance.CurrentMoney;

        SetupMinimapCamera();
    }

    void OnDestroy()
    {
        if (restartBtn != null)
            restartBtn.clicked -= OnRestartClicked;
        if (repairBtn != null)
            repairBtn.clicked -= OnRepairClicked;
        if (minimapRT != null)
            minimapRT.Release();
        if (minimapCam != null)
            Destroy(minimapCam.gameObject);

        PoliceCarController.OnPlayerArrested -= OnArrestDisplay;

        if (packageManager != null)
        {
            packageManager.OnDeliveryComplete -= OnDeliveryCompleteDisplay;
            packageManager.OnDeliveryFailed -= OnDeliveryFailedDisplay;
        }
    }

    void Update()
    {
        UpdateSpeed();
        UpdateHealthBar();
        UpdateWantedDisplay();
        UpdateMinimap();
        UpdateMoney();
        UpdateDeliveryPanel();
        UpdateArrestOverlay();
        UpdateDeliveryResultFlash();
    }

    // -----------------------------------------------------------
    //  Speed
    // -----------------------------------------------------------

    private void UpdateSpeed()
    {
        if (playerRb == null) return;

        float speedKmh = playerRb.linearVelocity.magnitude * 3.6f;
        float pct = Mathf.Clamp01(speedKmh / maxSpeedKmh);

        speedValue.text = Mathf.RoundToInt(speedKmh).ToString();
        speedBarFill.style.width = new Length(pct * 100f, LengthUnit.Percent);

        bool danger = wantedLevel != null && speedKmh > wantedLevel.speedingThreshold * 3.6f;
        speedPanel.EnableInClassList("speed-danger", danger);
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
        healthStrip.EnableInClassList("health-critical",
            critical && Mathf.PingPong(Time.time * 3f, 1f) > 0.5f);

        if (playerHealth.IsDead)
        {
            wreckedOverlay.style.display = DisplayStyle.Flex;
            // Update repair button text with cost
            if (repairBtn != null && playerHealth != null)
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
        wantedPanel.style.display = wanted ? DisplayStyle.Flex : DisplayStyle.None;
        if (!wanted) return;

        int stars = wantedLevel.Stars;
        starText.text = new string('\u2605', stars) + new string('\u2606', 5 - stars);

        starRow.EnableInClassList("star-flash",
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

        // Flash effect
        if (current != lastMoney)
        {
            bool gained = current > lastMoney;
            moneyPanel.EnableInClassList("money-flash", gained);
            moneyPanel.EnableInClassList("money-loss", !gained);
            lastMoney = current;
        }
        else
        {
            moneyPanel.RemoveFromClassList("money-flash");
            moneyPanel.RemoveFromClassList("money-loss");
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

        if (packageManager.HasPendingPickup)
        {
            deliveryStatusLabel.text = "Pick up package";
        }
        else
        {
            deliveryStatusLabel.text = "Deliver to destination";
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
        }
        else
        {
            deliveryPanel.RemoveFromClassList("timer-urgent");
        }
    }

    // -----------------------------------------------------------
    //  Arrest overlay
    // -----------------------------------------------------------

    private void OnArrestDisplay()
    {
        arrestDisplayTimer = 3f;
        // Calculate penalty text
        if (MoneyManager.Instance != null)
        {
            int penalty = Mathf.RoundToInt(MoneyManager.Instance.CurrentMoney * 0.3f);
            arrestPenalty.text = $"-${penalty}";
        }
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
        deliveryResultText.text = $"DELIVERED +${reward}";
        deliveryResultOverlay.EnableInClassList("delivery-success", true);
        deliveryResultOverlay.EnableInClassList("delivery-failed", false);
    }

    private void OnDeliveryFailedDisplay(string reason)
    {
        deliveryResultTimer = 2.5f;
        deliveryResultText.text = reason;
        deliveryResultOverlay.EnableInClassList("delivery-success", false);
        deliveryResultOverlay.EnableInClassList("delivery-failed", true);
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
