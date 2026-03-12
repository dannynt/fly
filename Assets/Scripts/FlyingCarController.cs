using UnityEngine;
using UnityEngine.InputSystem;

[RequireComponent(typeof(Rigidbody))]
public class FlyingCarController : MonoBehaviour
{
    [Header("Forward/Backward Movement (Car Style)")]
    [Tooltip("The absolute maximum speed the car can reach.")]
    public float maxForwardSpeed = 40f;
    [Tooltip("How fast the car accelerates from 0 to max speed.")]
    public float accelerationRate = 15f;
    [Tooltip("How fast the car naturally slows down when releasing the throttle.")]
    public float decelerationRate = 20f;
    [Tooltip("How strongly the physical engine fights to reach and maintain the target speed (Higher = Snappier, Lower = Slippier).")]
    public float engineGripStrength = 10f;

    [Header("Thruster Physics (Tank/Helicopter Style)")]
    [Tooltip("Vertical propulsion to fly up and down.")]
    public float verticalThrust = 6000f;
    [Tooltip("Rotational force to spin the car left and right (Yaw).")]
    public float turnTorque = 4000f;

    [Header("Juice & Game Feel Toggles")]
    [Tooltip("Toggle all visual and physical 'Juice' effects on or off.")]
    public bool enableAllJuice = true;
    [Tooltip("Physically tilts the car based on movement (Pitch and Roll).")]
    public bool enableDynamicTilt = true;
    [Tooltip("Adds a subtle vertical sinusoidal hover effect.")]
    public bool enableHoverBob = true;
    [Tooltip("Applies a physical recoil 'kick' when grabbing or releasing objects.")]
    public bool enableGrabRecoil = true;
    [Tooltip("Applies a cartoony squash and stretch effect based on vertical velocity.")]
    public bool enableCartoonySquash = false;
    [Tooltip("Maintains current altitude when not actively ascending or descending, like a helicopter.")]
    public bool enableHeightHold = true;
    [Tooltip("Adds pitch tilt, thruster rumble, and squash/stretch when ascending or descending.")]
    public bool enableVerticalJuice = true;

    [Header("Tilt Juice Tuning")]
    [Tooltip("Pitches the nose down when flying forward, up when reversing.")]
    public float maxPitchTilt = 22f;
    [Tooltip("Rolls the car heavily into the turn for a more dynamic feel.")]
    public float maxRollTilt = 35f;
    [Tooltip("How 'weighty' the ship feels when rolling/pitching. Higher = floats into the tilt, Lower = snaps into it.")]
    public float tiltSmoothTime = 0.15f;
    [Tooltip("How aggressively the thrusters fight to stabilize to the target angle.")]
    public float stabilizationStrength = 300f;
    
    [Header("Vertical Juice Tuning")]
    [Tooltip("Max pitch tilt (degrees) when ascending/descending. Nose tilts up when rising, down when diving.")]
    public float maxVerticalPitchTilt = 18f;
    [Tooltip("Random lateral jitter force when thrusting vertically, simulating thruster vibration.")]
    public float thrusterRumbleStrength = 800f;
    [Tooltip("How much the car stretches vertically when ascending/descending.")]
    public float verticalSquashStretchAmount = 0.12f;

    [Header("Bob & Height Tuning")]
    public float hoverBobAmplitude = 300f;
    public float hoverBobSpeed = 2.5f;
    [Tooltip("How strongly the car fights to stay at its target altitude.")]
    public float heightHoldStrength = 2000f;
    [Tooltip("Damping to prevent the height hold from oscillating like a bouncy spring.")]
    public float heightHoldDamping = 500f;

    [Header("Damping Settings")]
    [Tooltip("Stops the car from sliding forever.")]
    public float linearDrag = 3.5f;
    [Tooltip("Crucial for stopping the car from endlessly spinning and oscillating.")]
    public float angularDrag = 5f;
    [Range(0f, 1f)]
    public float hoverAssist = 0.95f;

    [Header("Grabbing Settings")]
    public Transform grabPoint;
    public float grabRadius = 3f;
    public LayerMask grabbableLayer;
    
    [Header("Input Actions")]
    public InputAction moveAction = new InputAction("Move", type: InputActionType.Value, expectedControlType: "Vector2");
    public InputAction throttleAction = new InputAction("Throttle", type: InputActionType.Value, expectedControlType: "Axis");
    public InputAction ascendAction = new InputAction("Ascend", type: InputActionType.Button);
    public InputAction descendAction = new InputAction("Descend", type: InputActionType.Button);
    public InputAction grabAction = new InputAction("Grab", type: InputActionType.Button);

    private Rigidbody rb;
    private VehicleHealth vehicleHealth;
    private bool isDead;
    
    // Inputs
    private Vector2 moveInput;
    private float verticalInput;

    // Grab State
    private Rigidbody grabbedObject;
    private FixedJoint grabJoint;
    private Collider[] myColliders;

    // Juice State
    private Vector3 originalScale;
    private float squashTarget = 1f;
    private float currentSquash = 1f;
    
    // Tilt Juice Mechanics
    private float currentPitchTarget;
    private float currentRollTarget;
    private float pitchVelocity;
    private float rollVelocity;

    // Height Hold State
    private float targetHeight;

    // Car Acceleration State
    private float currentTargetSpeed;

    void Awake()
    {
        // Setup default bindings
        if (moveAction.bindings.Count == 0)
        {
            moveAction.AddCompositeBinding("2DVector")
                .With("Up", "<Keyboard>/w")
                .With("Down", "<Keyboard>/s")
                .With("Left", "<Keyboard>/a")
                .With("Right", "<Keyboard>/d");
            
            // Limit joystick to the X-axis (Left/Right) for turning only. 
            // Avoids accidental speeding/braking when turning.
            moveAction.AddCompositeBinding("2DVector")
                .With("Left", "<Gamepad>/leftStick/left")
                .With("Right", "<Gamepad>/leftStick/right");
        }
        if (throttleAction.bindings.Count == 0)
        {
            throttleAction.AddCompositeBinding("1DAxis")
                .With("Positive", "<Gamepad>/rightTrigger")
                .With("Negative", "<Gamepad>/leftTrigger");
        }
        if (ascendAction.bindings.Count == 0)
        {
            ascendAction.AddBinding("<Keyboard>/space");
            ascendAction.AddBinding("<Gamepad>/rightShoulder");
        }
        if (descendAction.bindings.Count == 0)
        {
            descendAction.AddBinding("<Keyboard>/leftShift");
            descendAction.AddBinding("<Gamepad>/leftShoulder");
        }
        if (grabAction.bindings.Count == 0)
        {
            grabAction.AddBinding("<Keyboard>/e");
            grabAction.AddBinding("<Gamepad>/buttonSouth");
        }
    }

    private void OnEnable()
    {
        moveAction.Enable();
        throttleAction.Enable();
        ascendAction.Enable();
        descendAction.Enable();
        grabAction.Enable();

        grabAction.performed += OnGrabPerformed;
    }

    private void OnDisable()
    {
        moveAction.Disable();
        throttleAction.Disable();
        ascendAction.Disable();
        descendAction.Disable();
        grabAction.Disable();

        grabAction.performed -= OnGrabPerformed;
    }

    void Start()
    {
        rb = GetComponent<Rigidbody>();
        originalScale = transform.localScale;
        
        // Cache our car's colliders so we can prevent physics glitches when grabbing objects
        myColliders = GetComponentsInChildren<Collider>();
        
        rb.useGravity = true; 
        rb.linearDamping = linearDrag;
        rb.angularDamping = angularDrag;
        
        targetHeight = transform.position.y;

        vehicleHealth = GetComponent<VehicleHealth>();
        if (vehicleHealth != null)
        {
            vehicleHealth.OnDeath += OnVehicleDeath;
            vehicleHealth.OnRepaired += OnVehicleRepaired;
        }

        PoliceCarController.OnPlayerArrested += OnArrested;
    }

    void OnDestroy()
    {
        if (vehicleHealth != null)
        {
            vehicleHealth.OnDeath -= OnVehicleDeath;
            vehicleHealth.OnRepaired -= OnVehicleRepaired;
        }
        PoliceCarController.OnPlayerArrested -= OnArrested;
    }

    private void OnVehicleDeath()
    {
        isDead = true;
        // Release any grabbed object
        if (grabbedObject != null) Release();
        // Remove hover so the car falls
        rb.linearDamping = 0.5f;
        rb.angularDamping = 0.5f;
    }

    private void OnVehicleRepaired(float health)
    {
        isDead = false;
        rb.linearDamping = linearDrag;
        rb.angularDamping = angularDrag;
        targetHeight = transform.position.y;
    }

    private float arrestFreezeTimer;

    private void OnArrested()
    {
        arrestFreezeTimer = 3f;
    }

    void Update()
    {
        if (isDead) return;

        // Arrest freeze — block input temporarily
        if (arrestFreezeTimer > 0f)
        {
            arrestFreezeTimer -= Time.deltaTime;
            moveInput = Vector2.zero;
            verticalInput = 0f;
            return;
        }

        HandleInputs();
        
        if (enableAllJuice)
        {
            HandleJuicyVisuals();
        }
        else
        {
            // Reset scale if juice gets turned off mid-flight
            transform.localScale = originalScale;
        }
    }

    void FixedUpdate()
    {
        if (isDead) return;

        ApplyFlightPhysics();
    }

    private void HandleInputs()
    {
        // X = Turn (Yaw). Y is still calculated by WASD keyboard up/down as fallback.
        Vector2 rawMove = moveAction.ReadValue<Vector2>();
        float rawThrottle = throttleAction.ReadValue<float>();

        // We combine the Trigger axes with the WASD fallback
        float finalThrottle = Mathf.Abs(rawThrottle) > 0.01f ? rawThrottle : rawMove.y;
        
        moveInput.x = rawMove.x;
        moveInput.y = finalThrottle;

        verticalInput = 0f;
        if (ascendAction.IsPressed()) verticalInput = 1f;
        else if (descendAction.IsPressed()) verticalInput = -1f;
    }

    private void ApplyFlightPhysics()
    {
        // 1. Forward / Backward Thrust (Car Acceleration Style)
        if (Mathf.Abs(moveInput.y) > 0.01f)
        {
            // Gradually build up to the max speed requested by the player
            currentTargetSpeed = Mathf.MoveTowards(currentTargetSpeed, moveInput.y * maxForwardSpeed, accelerationRate * Time.fixedDeltaTime);
        }
        else
        {
            // Naturally decelerate to 0 when there covers no input
            currentTargetSpeed = Mathf.MoveTowards(currentTargetSpeed, 0f, decelerationRate * Time.fixedDeltaTime);
        }

        // Measure how fast we are currently moving on our local Z-axis (Forward/Backward)
        float currentLocalZSpeed = transform.InverseTransformDirection(rb.linearVelocity).z;
        
        // Find the difference between how fast we WANT to go, and how fast we ARE going
        float speedDifference = currentTargetSpeed - currentLocalZSpeed;
        
        // Apply a proportional force based on the error to reach the target speed smoothly
        float propelForce = speedDifference * rb.mass * engineGripStrength;
        rb.AddRelativeForce(Vector3.forward * propelForce * Time.fixedDeltaTime, ForceMode.Force);

        // 2. Ascend / Descend & Height Hold
        if (Mathf.Abs(verticalInput) > 0.01f)
        {
            // Active Input
            rb.AddForce(Vector3.up * verticalInput * verticalThrust * Time.fixedDeltaTime, ForceMode.Force);
            targetHeight = transform.position.y; // Keep updating target height while actively moving
        }
        else if (enableHeightHold)
        {
            // Passive Height Holding using a PD Controller (Spring/Damper)
            float heightError = targetHeight - transform.position.y;
            float holdForce = (heightError * heightHoldStrength) - (rb.linearVelocity.y * heightHoldDamping);
            
            // Apply hold force (scaled by mass so heavy ships don't drop instantly)
            rb.AddForce(Vector3.up * holdForce * rb.mass * Time.fixedDeltaTime, ForceMode.Force);
        }

        // 3. Hover Assist (Counteract Gravity)
        Vector3 antiGravityForce = -Physics.gravity * rb.mass * hoverAssist;
        rb.AddForce(antiGravityForce * Time.fixedDeltaTime, ForceMode.Force);

        // 4. Yaw (Turning Around Y-Axis)
        rb.AddRelativeTorque(Vector3.up * moveInput.x * turnTorque * Time.fixedDeltaTime, ForceMode.Force);

        // Apply Juice Physics
        if (enableAllJuice)
        {
            if (enableHoverBob)
            {
                float bobForce = Mathf.Sin(Time.time * hoverBobSpeed) * hoverBobAmplitude;
                rb.AddForce(Vector3.up * bobForce * Time.fixedDeltaTime, ForceMode.Force);
            }

            if (enableDynamicTilt)
            {
                // What rotational angle SHOULD the car be at based on our speed (instead of raw input now)?
                // We normalize it against maxForwardSpeed so the tilt builds up with the acceleration!
                float normalizedSpeed = currentLocalZSpeed / maxForwardSpeed;
                float desiredPitch = normalizedSpeed * maxPitchTilt;

                // Vertical juice: tilt nose up when ascending, nose down when descending
                if (enableVerticalJuice)
                    desiredPitch += -verticalInput * maxVerticalPitchTilt;

                float desiredRoll = -moveInput.x * maxRollTilt;

                // JUICE UPGRADE: SmoothDamp creates a weighty, spring-like feel. 
                currentPitchTarget = Mathf.SmoothDamp(currentPitchTarget, desiredPitch, ref pitchVelocity, tiltSmoothTime);
                currentRollTarget = Mathf.SmoothDamp(currentRollTarget, desiredRoll, ref rollVelocity, tiltSmoothTime);

                // Preserve the current Yaw (Y rotation), but enforce new smoothed Pitch and Roll
                Quaternion currentYawRot = Quaternion.Euler(0, rb.rotation.eulerAngles.y, 0);
                Quaternion desiredRot = currentYawRot * Quaternion.Euler(currentPitchTarget, 0, currentRollTarget);

                // Find the shortest rotation to get from current to desired
                Quaternion deltaRot = desiredRot * Quaternion.Inverse(rb.rotation);
                deltaRot.ToAngleAxis(out float angle, out Vector3 axis);
                if (angle > 180f) angle -= 360f;

                // Apply a powerful corrective torque to align the ship
                if (Mathf.Abs(angle) > 0.1f)
                {
                    Vector3 correctionTorque = axis.normalized * (angle * stabilizationStrength);
                    rb.AddTorque(correctionTorque * rb.mass * Time.fixedDeltaTime, ForceMode.Force);
                }
            }

            // Thruster rumble — small random lateral jitter when ascending/descending
            if (enableVerticalJuice && Mathf.Abs(verticalInput) > 0.01f)
            {
                Vector3 rumble = new Vector3(
                    Random.Range(-1f, 1f),
                    0f,
                    Random.Range(-1f, 1f)
                ) * thrusterRumbleStrength * Mathf.Abs(verticalInput);
                rb.AddForce(rumble * Time.fixedDeltaTime, ForceMode.Force);
            }
        }
        else if (enableDynamicTilt) // If AllJuice is off but we still want to stabilize flat
        {
            // Auto-stabilize to flat (0 pitch, 0 roll)
            Quaternion flatRot = Quaternion.Euler(0, rb.rotation.eulerAngles.y, 0);
            Quaternion deltaRot = flatRot * Quaternion.Inverse(rb.rotation);
            deltaRot.ToAngleAxis(out float angle, out Vector3 axis);
            if (angle > 180f) angle -= 360f;
            
            if (Mathf.Abs(angle) > 0.1f)
            {
                Vector3 correctionTorque = axis.normalized * (angle * stabilizationStrength * 0.5f);
                rb.AddTorque(correctionTorque * rb.mass * Time.fixedDeltaTime, ForceMode.Force);
            }
        }
    }

    private void HandleJuicyVisuals()
    {
        // Revert squash impulse back to 1 over time
        currentSquash = Mathf.Lerp(currentSquash, 1f, Time.deltaTime * 5f);

        float verticalVel = rb.linearVelocity.y;
        float totalStretchY = 0f;
        float totalStretchXZ = 0f;

        // Cartoony squash from vertical velocity (original behavior)
        if (enableCartoonySquash)
        {
            float cartoonyStretch = Mathf.Clamp(verticalVel * 0.02f, -0.3f, 0.3f);
            totalStretchY += cartoonyStretch + (currentSquash - 1f);
            totalStretchXZ += -cartoonyStretch * 0.5f;
        }

        // Vertical juice squash/stretch — subtle body deformation when thrusting up/down
        if (enableVerticalJuice && Mathf.Abs(verticalInput) > 0.01f)
        {
            float vStretch = verticalInput * verticalSquashStretchAmount;
            totalStretchY += vStretch;
            totalStretchXZ += -vStretch * 0.5f;
        }

        bool hasEffect = enableCartoonySquash || (enableVerticalJuice && Mathf.Abs(verticalInput) > 0.01f);
        if (hasEffect)
        {
            Vector3 targetScale = originalScale + new Vector3(totalStretchXZ, totalStretchY, totalStretchXZ);
            transform.localScale = Vector3.Lerp(transform.localScale, targetScale, Time.deltaTime * 10f);
        }
        else
        {
            transform.localScale = originalScale;
        }
    }

    private void OnGrabPerformed(InputAction.CallbackContext context)
    {
        if (grabbedObject == null) TryGrab();
        else Release();
    }

    private void TryGrab()
    {
        Vector3 searchPosition = grabPoint != null ? grabPoint.position : transform.position;
        Collider[] colliders = Physics.OverlapSphere(searchPosition, grabRadius, grabbableLayer);

        foreach (var col in colliders)
        {
            Rigidbody targetRb = col.attachedRigidbody;
            
            if (targetRb != null && !targetRb.isKinematic)
            {
                grabbedObject = targetRb;

                // Stop grabbed object from violently pushing the car if their colliders overlap
                Collider[] grabbedColliders = grabbedObject.GetComponentsInChildren<Collider>();
                foreach (var myCol in myColliders)
                {
                    foreach (var grabCol in grabbedColliders)
                    {
                        Physics.IgnoreCollision(myCol, grabCol, true);
                    }
                }

                if (grabPoint != null)
                {
                    grabbedObject.transform.position = grabPoint.position;
                }

                grabJoint = gameObject.AddComponent<FixedJoint>();
                grabJoint.connectedBody = grabbedObject;

                Debug.Log($"Grabbed: {grabbedObject.name}");

                if (enableAllJuice)
                {
                    if (enableCartoonySquash) 
                        currentSquash = 1.25f; // Visual pop
                        
                    if (enableGrabRecoil)
                        rb.AddForce(-transform.up * (rb.mass * 5f), ForceMode.Impulse); // Physical kickback
                }

                break; 
            }
        }
    }

    private void Release()
    {
        if (grabJoint != null)
        {
            Destroy(grabJoint);
            grabJoint = null;
        }

        if (grabbedObject != null)
        {
            // Re-enable collisions so it can bounce off the car again later
            Collider[] grabbedColliders = grabbedObject.GetComponentsInChildren<Collider>();
            foreach (var myCol in myColliders)
            {
                foreach (var grabCol in grabbedColliders)
                {
                    Physics.IgnoreCollision(myCol, grabCol, false);
                }
            }

            grabbedObject.WakeUp();
            Debug.Log($"Released: {grabbedObject.name}");
            grabbedObject = null;
            
            if (enableAllJuice)
            {
                if (enableCartoonySquash) 
                    currentSquash = 0.8f; // Visual pop
                    
                if (enableGrabRecoil)
                    rb.AddForce(transform.up * (rb.mass * 5f), ForceMode.Impulse); // Physical kickback
            }
        }
    }

    private void OnDrawGizmosSelected()
    {
        Gizmos.color = Color.green;
        Vector3 pos = grabPoint != null ? grabPoint.position : transform.position;
        Gizmos.DrawWireSphere(pos, grabRadius);
    }
}
