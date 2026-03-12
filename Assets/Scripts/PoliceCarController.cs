using UnityEngine;

/// <summary>
/// Police car that homes in on the player like a rocket.
/// Uses smooth pursuit-with-lead steering, forward thrust, and stays mostly upright.
/// </summary>
[RequireComponent(typeof(Rigidbody))]
public class PoliceCarController : MonoBehaviour
{
    public enum PoliceState { Idle, Chasing, Returning, Despawning }

    [Header("Thrust")]
    [Tooltip("Forward thrust acceleration (m/s²)")]
    public float thrust = 30f;
    [Tooltip("Normal top speed")]
    public float maxSpeed = 50f;
    [Tooltip("Boosted top speed when far from target")]
    public float boostSpeed = 70f;
    [Tooltip("Distance to start boosting")]
    public float boostDistance = 45f;

    [Header("Steering")]
    [Tooltip("How fast the car rotates toward the target (degrees/sec)")]
    public float steerRate = 270f;
    [Tooltip("How many seconds ahead to predict target position")]
    public float leadTime = 0.8f;

    [Header("Height")]
    [Tooltip("Height offset above the player")]
    public float heightOffset = 1.5f;
    [Tooltip("How strongly it corrects toward target height")]
    public float heightForce = 30f;
    [Tooltip("Damping to prevent vertical oscillation")]
    public float heightDamping = 8f;

    [Header("Chase Limits")]
    [Tooltip("Give up distance")]
    public float maxChaseDistance = 200f;
    [Tooltip("Ease off throttle within this distance")]
    public float closeDistance = 6f;

    [Header("Arrest")]
    [Tooltip("Distance at which the police car arrests the player on contact")]
    public float arrestDistance = 4f;
    [Tooltip("Money penalty when arrested (percentage of current money)")]
    [Range(0f, 1f)]
    public float arrestMoneyPenalty = 0.3f;
    [Tooltip("Seconds after arrest before player regains control")]
    public float arrestFreezeDuration = 3f;

    [Header("Physics")]
    public float drag = 2f;

    [HideInInspector] public Transform target;
    public PoliceState State { get; private set; } = PoliceState.Idle;

    /// <summary>Fires when this police car arrests the player.</summary>
    public static event System.Action OnPlayerArrested;

    private Rigidbody rb;
    private Rigidbody targetRb;
    private Vector3 returnPosition;
    private static float lastArrestTime = -999f;

    void Start()
    {
        rb = GetComponent<Rigidbody>();
        rb.useGravity = false;
        rb.linearDamping = 0f;
        rb.angularDamping = 10f;
        returnPosition = transform.position;
    }

    void FixedUpdate()
    {
        switch (State)
        {
            case PoliceState.Idle:
                DoIdle();
                break;
            case PoliceState.Chasing:
                DoChase();
                break;
            case PoliceState.Returning:
                DoReturn();
                break;
        }
    }

    // ------------------------------------------------------------------ //
    //  Public API
    // ------------------------------------------------------------------ //

    public void BeginChase(Transform chaseTarget)
    {
        target = chaseTarget;
        targetRb = chaseTarget != null ? chaseTarget.GetComponent<Rigidbody>() : null;
        State = PoliceState.Chasing;
        returnPosition = transform.position;
    }

    public void StopChase()
    {
        target = null;
        targetRb = null;
        State = PoliceState.Returning;
    }

    // ------------------------------------------------------------------ //
    //  Idle — hover in place
    // ------------------------------------------------------------------ //

    private void DoIdle()
    {
        // Damp to stop
        rb.linearVelocity = Vector3.Lerp(rb.linearVelocity, Vector3.zero, 3f * Time.fixedDeltaTime);
        // Level out
        SteerToward(transform.position + transform.forward, 90f);
    }

    // ------------------------------------------------------------------ //
    //  Chase — rocket homing
    // ------------------------------------------------------------------ //

    private void DoChase()
    {
        if (target == null) { StopChase(); return; }

        float dist = Vector3.Distance(transform.position, target.position);
        if (dist > maxChaseDistance) { StopChase(); return; }

        // Predict where the target will be
        Vector3 tgtVel = targetRb != null ? targetRb.linearVelocity : Vector3.zero;
        Vector3 predictedPos = target.position + tgtVel * leadTime;
        // Keep target height with offset
        predictedPos.y = target.position.y + heightOffset;

        // Steer yaw only (horizontal plane) so thrust doesn't push vertically
        Vector3 flatPredicted = new Vector3(predictedPos.x, transform.position.y, predictedPos.z);
        SteerToward(flatPredicted, steerRate);

        // Thrust along forward (stays horizontal because we steer in the flat plane)
        float speedCap = dist > boostDistance ? boostSpeed : maxSpeed;
        float throttle = dist < closeDistance ? 0.15f : 1f;

        Vector3 toTarget = (flatPredicted - transform.position).normalized;
        float alignment = Mathf.Max(0f, Vector3.Dot(transform.forward, toTarget));
        float accel = thrust * throttle * alignment;

        rb.AddForce(transform.forward * accel, ForceMode.Acceleration);

        // Drag proportional to speed² for natural speed limiting
        Vector3 vel = rb.linearVelocity;
        float speed = vel.magnitude;
        if (speed > 0.1f)
        {
            float dragForce = drag * speed / speedCap;
            rb.AddForce(-vel.normalized * dragForce * speed, ForceMode.Acceleration);
        }

        // Vertical correction with damping (spring-damper, no oscillation)
        float heightError = predictedPos.y - transform.position.y;
        float verticalCorrection = heightError * heightForce - rb.linearVelocity.y * heightDamping;
        rb.AddForce(Vector3.up * verticalCorrection, ForceMode.Acceleration);

        // Counteract gravity
        rb.AddForce(-Physics.gravity, ForceMode.Acceleration);

        // Arrest check — close enough to player
        if (dist < arrestDistance && Time.time - lastArrestTime > arrestFreezeDuration + 2f)
        {
            ArrestPlayer();
        }
    }

    private void ArrestPlayer()
    {
        lastArrestTime = Time.time;

        // Take money
        if (MoneyManager.Instance != null)
        {
            int penalty = Mathf.RoundToInt(MoneyManager.Instance.CurrentMoney * arrestMoneyPenalty);
            if (penalty > 0)
                MoneyManager.Instance.ChangeMoney(-penalty);
        }

        // Clear wanted level
        var wl = target != null ? target.GetComponent<WantedLevel>() : null;
        if (wl != null)
            wl.AddHeat(-wl.CurrentHeat);

        // Fail any active delivery
        var pm = FindAnyObjectByType<PackageManager>();
        if (pm != null && pm.HasActiveDelivery)
            pm.FailDelivery("ARRESTED");

        OnPlayerArrested?.Invoke();
    }

    // ------------------------------------------------------------------ //
    //  Return — fly back and despawn
    // ------------------------------------------------------------------ //

    private void DoReturn()
    {
        Vector3 toReturn = returnPosition - transform.position;
        if (toReturn.magnitude < 10f)
        {
            State = PoliceState.Despawning;
            Destroy(gameObject, 0.5f);
            return;
        }

        Vector3 flatReturn = new Vector3(returnPosition.x, transform.position.y, returnPosition.z);
        SteerToward(flatReturn, steerRate * 0.5f);
        rb.AddForce(transform.forward * thrust * 0.4f, ForceMode.Acceleration);

        // Drag
        rb.AddForce(-rb.linearVelocity * drag * 0.5f, ForceMode.Acceleration);

        // Height hold at return height with damping
        float hErr = (returnPosition.y + 10f) - transform.position.y;
        rb.AddForce(Vector3.up * (hErr * heightForce - rb.linearVelocity.y * heightDamping), ForceMode.Acceleration);

        // Anti-gravity
        rb.AddForce(-Physics.gravity, ForceMode.Acceleration);
    }

    // ------------------------------------------------------------------ //
    //  Steering — rotate to face a world point, staying upright
    // ------------------------------------------------------------------ //

    private void SteerToward(Vector3 worldPoint, float rate)
    {
        Vector3 dir = worldPoint - transform.position;
        if (dir.sqrMagnitude < 0.01f) return;

        // Target rotation that looks at the point but keeps world-up
        Quaternion targetRot = Quaternion.LookRotation(dir.normalized, Vector3.up);

        // Smoothly rotate toward it
        float step = rate * Time.fixedDeltaTime;
        Quaternion newRot = Quaternion.RotateTowards(rb.rotation, targetRot, step);
        rb.MoveRotation(newRot);
    }
}
