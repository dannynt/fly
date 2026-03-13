using UnityEngine;

[RequireComponent(typeof(Rigidbody))]
public class AIFlyingCarController : MonoBehaviour
{
    public enum AIState { Cruising, Descending, Parked, Ascending }

    [Header("Movement")]
    public float maxSpeed = 25f;
    public float accelerationRate = 12f;
    public float decelerationRate = 15f;
    public float engineGripStrength = 8f;

    [Header("Turning")]
    public float turnTorque = 3000f;
    [Tooltip("How aggressively the AI steers toward waypoints")]
    public float steeringSensitivity = 2f;
    [Tooltip("Angle threshold that causes the car to slow down for turns")]
    public float slowdownAngle = 45f;

    [Header("Hover")]
    public float flyHeight = 8f;
    public float heightHoldStrength = 2000f;
    public float heightHoldDamping = 500f;
    [Range(0f, 1f)]
    public float hoverAssist = 0.95f;

    [Header("Altitude Variety")]
    [Tooltip("Gentle sinusoidal altitude drift amplitude while cruising")]
    public float altitudeDriftAmount = 2f;
    [Tooltip("Speed of the altitude drift oscillation")]
    public float altitudeDriftSpeed = 0.4f;

    [Header("Landing / Parking")]
    [Tooltip("Height above ground when parked")]
    public float landedHeight = 0.5f;
    [Tooltip("How fast the car descends/ascends (m/s target height change)")]
    public float verticalTransitionSpeed = 4f;
    [Tooltip("Minimum seconds spent parked on the ground")]
    public float minParkTime = 3f;
    [Tooltip("Maximum seconds spent parked on the ground")]
    public float maxParkTime = 8f;
    [Tooltip("Minimum seconds between landing attempts while cruising")]
    public float minCruiseTime = 10f;
    [Tooltip("Maximum seconds between landing attempts while cruising")]
    public float maxCruiseTime = 30f;
    [Tooltip("Chance (0-1) the car will actually land when the timer fires")]
    [Range(0f, 1f)]
    public float landingChance = 0.3f;
    [Tooltip("Chance (0-1) to land on a building rooftop instead of the ground")]
    [Range(0f, 1f)]
    public float roofLandingChance = 0.5f;
    [Tooltip("Speed multiplier while descending/ascending (slower near ground)")]
    public float transitionSpeedMult = 0.4f;

    [Header("Visual Tilt")]
    public float maxPitchTilt = 15f;
    public float maxRollTilt = 25f;
    public float tiltSmoothTime = 0.15f;
    public float stabilizationStrength = 300f;

    [Header("Vertical Juice")]
    [Tooltip("Pitch tilt (degrees) when ascending/descending. Nose up when rising, down when diving.")]
    public float maxVerticalPitchTilt = 15f;
    [Tooltip("How much the car stretches vertically during altitude transitions.")]
    public float verticalSquashStretchAmount = 0.08f;
    [Tooltip("Upward impulse burst when taking off from parked.")]
    public float takeoffBurstForce = 3000f;

    [Header("Damping")]
    public float linearDrag = 3f;
    public float angularDrag = 5f;

    [Header("Waypoint Following")]
    public float waypointArrivalDistance = 5f;

    [Header("Collision Avoidance")]
    public float detectionRange = 15f;
    public float brakeDistance = 8f;

    [HideInInspector] public Vector3[] waypoints;
    [HideInInspector] public bool isLoop = true;
    [HideInInspector] public int currentWaypointIndex;

    private Rigidbody rb;
    private VehicleHealth vehicleHealth;
    private bool isDead;
    private float turnInput;
    private float throttleInput;
    private float currentPitchTarget;
    private float currentRollTarget;
    private float pitchVelocity;
    private float rollVelocity;
    private float currentTargetSpeed;

    // Vertical juice state
    private Vector3 originalScale;

    // State machine
    private AIState state = AIState.Cruising;
    private float currentTargetHeight;
    private float landingTargetHeight;
    private float stateTimer;
    private float driftPhaseOffset;

    void Start()
    {
        rb = GetComponent<Rigidbody>();
        rb.useGravity = true;
        rb.linearDamping = linearDrag;
        rb.angularDamping = angularDrag;

        originalScale = transform.localScale;
        currentTargetHeight = flyHeight;
        stateTimer = Random.Range(minCruiseTime, maxCruiseTime);
        driftPhaseOffset = Random.Range(0f, Mathf.PI * 2f);

        vehicleHealth = GetComponent<VehicleHealth>();
        if (vehicleHealth != null)
            vehicleHealth.OnDeath += OnVehicleDeath;
    }

    void OnDestroy()
    {
        if (vehicleHealth != null)
            vehicleHealth.OnDeath -= OnVehicleDeath;
    }

    private void OnVehicleDeath()
    {
        isDead = true;
        rb.linearDamping = 0.5f;
        rb.angularDamping = 0.5f;
    }

    void Update()
    {
        if (isDead) return;
        ApplyVerticalJuiceVisuals();
    }

    void FixedUpdate()
    {
        if (isDead) return;
        if (waypoints == null || waypoints.Length < 2) return;
        UpdateState();
        ComputeAIInputs();
        ApplyPhysics();
    }

    // ------------------------------------------------------------------ //
    //  State Machine
    // ------------------------------------------------------------------ //

    private void UpdateState()
    {
        stateTimer -= Time.fixedDeltaTime;

        switch (state)
        {
            case AIState.Cruising:
                // Gentle altitude drift while flying
                float drift = Mathf.Sin(Time.time * altitudeDriftSpeed + driftPhaseOffset) * altitudeDriftAmount;
                currentTargetHeight = flyHeight + drift;

                if (stateTimer <= 0f)
                {
                    if (Random.value < landingChance)
                    {
                        state = AIState.Descending;
                        landingTargetHeight = FindLandingHeight();
                    }
                    stateTimer = Random.Range(minCruiseTime, maxCruiseTime);
                }
                break;

            case AIState.Descending:
                // Gradually lower target height for a smooth descent
                currentTargetHeight = Mathf.MoveTowards(currentTargetHeight, landingTargetHeight, verticalTransitionSpeed * Time.fixedDeltaTime);

                if (Mathf.Abs(transform.position.y - landingTargetHeight) < 0.5f &&
                    Mathf.Abs(rb.linearVelocity.y) < 0.5f)
                {
                    state = AIState.Parked;
                    stateTimer = Random.Range(minParkTime, maxParkTime);
                }
                break;

            case AIState.Parked:
                // Sit idle, engine off
                throttleInput = 0f;
                turnInput = 0f;
                if (stateTimer <= 0f)
                {
                    state = AIState.Ascending;
                    // Takeoff burst — a satisfying upward kick when lifting off
                    rb.AddForce(Vector3.up * takeoffBurstForce, ForceMode.Impulse);
                }
                break;

            case AIState.Ascending:
                // Gradually raise target height for a smooth ascent
                currentTargetHeight = Mathf.MoveTowards(currentTargetHeight, flyHeight, verticalTransitionSpeed * Time.fixedDeltaTime);

                if (Mathf.Abs(transform.position.y - flyHeight) < 1.5f)
                {
                    state = AIState.Cruising;
                    stateTimer = Random.Range(minCruiseTime, maxCruiseTime);
                }
                break;
        }
    }

    // ------------------------------------------------------------------ //
    //  AI Inputs
    // ------------------------------------------------------------------ //

    private void ComputeAIInputs()
    {
        // When parked, don't compute driving inputs
        if (state == AIState.Parked) return;

        Vector3 target = waypoints[currentWaypointIndex];
        Vector3 flatPos = new Vector3(transform.position.x, 0f, transform.position.z);
        Vector3 flatTarget = new Vector3(target.x, 0f, target.z);

        Vector3 toTarget = flatTarget - flatPos;
        float distance = toTarget.magnitude;

        if (distance < waypointArrivalDistance)
        {
            if (isLoop)
                currentWaypointIndex = (currentWaypointIndex + 1) % waypoints.Length;
            else
                currentWaypointIndex = Mathf.Min(currentWaypointIndex + 1, waypoints.Length - 1);
            return;
        }

        // Steering
        float signedAngle = Vector3.SignedAngle(transform.forward, toTarget.normalized, Vector3.up);
        turnInput = Mathf.Clamp(signedAngle * steeringSensitivity / 90f, -1f, 1f);

        // Throttle (slow down on sharp turns)
        float absAngle = Mathf.Abs(signedAngle);
        float alignment = Mathf.Clamp01(1f - absAngle / slowdownAngle);
        throttleInput = Mathf.Lerp(0.3f, 1f, alignment);

        // Gradually slow during descent, speed up during ascent
        if (state == AIState.Descending)
        {
            float descentProgress = Mathf.InverseLerp(flyHeight, landingTargetHeight, currentTargetHeight);
            throttleInput *= Mathf.Lerp(1f, transitionSpeedMult, descentProgress);
        }
        else if (state == AIState.Ascending)
        {
            float ascentProgress = Mathf.InverseLerp(0f, flyHeight, currentTargetHeight);
            throttleInput *= Mathf.Lerp(transitionSpeedMult, 1f, ascentProgress);
        }

        // Collision avoidance — brake when a rigidbody (another car) is ahead
        if (Physics.Raycast(transform.position, transform.forward, out RaycastHit hit, detectionRange))
        {
            if (hit.rigidbody != null && hit.distance < brakeDistance)
            {
                throttleInput *= hit.distance / brakeDistance;
            }
        }
    }

    // ------------------------------------------------------------------ //
    //  Physics
    // ------------------------------------------------------------------ //

    private void ApplyPhysics()
    {
        // 1. Forward thrust (car-style acceleration)
        if (state == AIState.Parked)
        {
            currentTargetSpeed = Mathf.MoveTowards(currentTargetSpeed, 0f, decelerationRate * Time.fixedDeltaTime);
        }
        else if (throttleInput > 0.01f)
        {
            currentTargetSpeed = Mathf.MoveTowards(currentTargetSpeed, throttleInput * maxSpeed, accelerationRate * Time.fixedDeltaTime);
        }
        else
        {
            currentTargetSpeed = Mathf.MoveTowards(currentTargetSpeed, 0f, decelerationRate * Time.fixedDeltaTime);
        }

        float currentLocalZSpeed = transform.InverseTransformDirection(rb.linearVelocity).z;
        float speedDiff = currentTargetSpeed - currentLocalZSpeed;
        rb.AddRelativeForce(Vector3.forward * speedDiff * rb.mass * engineGripStrength * Time.fixedDeltaTime, ForceMode.Force);

        // 2. Yaw turning
        rb.AddRelativeTorque(Vector3.up * turnInput * turnTorque * Time.fixedDeltaTime, ForceMode.Force);

        // 3. Height hold — smoothly transition toward currentTargetHeight
        float heightError = currentTargetHeight - transform.position.y;
        float holdForce = (heightError * heightHoldStrength) - (rb.linearVelocity.y * heightHoldDamping);
        rb.AddForce(Vector3.up * holdForce * rb.mass * Time.fixedDeltaTime, ForceMode.Force);

        // 4. Anti-gravity hover assist (reduce when parked on the ground)
        float assistMult = state == AIState.Parked ? 0f : hoverAssist;
        rb.AddForce(-Physics.gravity * rb.mass * assistMult, ForceMode.Force);

        // 5. Dynamic tilt (pitch when accelerating, roll when turning)
        float normalizedSpeed = currentLocalZSpeed / maxSpeed;
        float desiredPitch = normalizedSpeed * maxPitchTilt;

        // Vertical juice: tilt nose up when ascending, nose down when descending
        if (state == AIState.Ascending)
            desiredPitch += -maxVerticalPitchTilt;
        else if (state == AIState.Descending)
            desiredPitch += maxVerticalPitchTilt;

        float desiredRoll = -turnInput * maxRollTilt;

        currentPitchTarget = Mathf.SmoothDamp(currentPitchTarget, desiredPitch, ref pitchVelocity, tiltSmoothTime);
        currentRollTarget = Mathf.SmoothDamp(currentRollTarget, desiredRoll, ref rollVelocity, tiltSmoothTime);

        Quaternion currentYawRot = Quaternion.Euler(0f, rb.rotation.eulerAngles.y, 0f);
        Quaternion desiredRot = currentYawRot * Quaternion.Euler(currentPitchTarget, 0f, currentRollTarget);

        Quaternion deltaRot = desiredRot * Quaternion.Inverse(rb.rotation);
        deltaRot.ToAngleAxis(out float angle, out Vector3 axis);
        if (angle > 180f) angle -= 360f;

        if (Mathf.Abs(angle) > 0.1f)
        {
            Vector3 correctionTorque = axis.normalized * (angle * stabilizationStrength);
            rb.AddTorque(correctionTorque * rb.mass * Time.fixedDeltaTime, ForceMode.Force);
        }
    }

    private float FindLandingHeight()
    {
        float groundHeight = landedHeight;

        // Find surface directly below
        if (Physics.Raycast(transform.position, Vector3.down, out RaycastHit groundHit, 200f))
            groundHeight = groundHit.point.y + landedHeight;

        // Search nearby for building rooftops
        float bestRoofHeight = -1f;
        float searchRadius = 18f;
        int numChecks = 8;
        for (int i = 0; i < numChecks; i++)
        {
            float angle = i * (360f / numChecks) * Mathf.Deg2Rad;
            Vector3 checkPos = transform.position + new Vector3(Mathf.Cos(angle) * searchRadius, 0f, Mathf.Sin(angle) * searchRadius);
            checkPos.y = flyHeight + 50f;

            if (Physics.Raycast(checkPos, Vector3.down, out RaycastHit hit, 200f))
            {
                float surfaceY = hit.point.y;
                if (surfaceY > 3f && surfaceY < transform.position.y - 2f && surfaceY > bestRoofHeight)
                    bestRoofHeight = surfaceY;
            }
        }

        if (bestRoofHeight > 0f && Random.value < roofLandingChance)
            return bestRoofHeight + landedHeight;

        return groundHeight;
    }

    private void ApplyVerticalJuiceVisuals()
    {
        bool transitioning = state == AIState.Ascending || state == AIState.Descending;
        if (transitioning)
        {
            // Stretch vertically when ascending, squash when descending
            float dir = state == AIState.Ascending ? 1f : -1f;
            float stretch = dir * verticalSquashStretchAmount;
            Vector3 target = originalScale + new Vector3(-stretch * 0.5f, stretch, -stretch * 0.5f);
            transform.localScale = Vector3.Lerp(transform.localScale, target, Time.deltaTime * 8f);
        }
        else
        {
            transform.localScale = Vector3.Lerp(transform.localScale, originalScale, Time.deltaTime * 5f);
        }
    }
}
