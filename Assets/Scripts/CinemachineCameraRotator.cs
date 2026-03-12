using UnityEngine;
using UnityEngine.InputSystem;
using Unity.Cinemachine;

public class CinemachineCameraRotator : MonoBehaviour
{
    [Header("Sensitivity Settings")]
    [Tooltip("Rotation sensitivity for Mouse.")]
    public float mouseSensitivity = 0.5f;

    [Tooltip("Rotation sensitivity for Gamepad Joystick.")]
    public float joystickSensitivity = 150f;

    [Tooltip("Invert the Y axis (up/down).")]
    public bool invertY = false;

    [Tooltip("Clamp angles for X rotation (Pitch).")]
    public float minPitch = -80f;
    public float maxPitch = 80f;

    [Header("Input Setup")]
    public InputAction lookAction = new InputAction("Look", type: InputActionType.Value, expectedControlType: "Vector2");

    private float _pitch;
    private float _yaw;

    void Awake()
    {
        if (lookAction.bindings.Count == 0)
        {
            // Mouse binding
            lookAction.AddBinding("<Mouse>/delta");
            // Left Joystick binding
            lookAction.AddBinding("<Gamepad>/rightStick");
        }
    }

    void OnEnable()
    {
        lookAction.Enable();
    }

    void OnDisable()
    {
        lookAction.Disable();
    }

    void Start()
    {
        // Initialize our internal yaw and pitch based on the current rotation
        Vector3 rot = transform.eulerAngles;
        _pitch = rot.x;
        _yaw = rot.y;

        // Adjust pitch to be in the -180 to 180 range instead of 0 to 360
        if (_pitch > 180f) _pitch -= 360f;
    }

    void Update()
    {
        if (lookAction == null) return;

        Vector2 lookInput = lookAction.ReadValue<Vector2>();

        // We check if the input is coming from a mouse or a gamepad
        bool isMouse = lookAction.activeControl?.device is Mouse;

        // Mouse delta doesn't need deltaTime because it's physical pixels moved since last frame.
        // Joystick needs deltaTime because it's a continuous value (0 to 1) held over time.
        float sensitivity = isMouse ? mouseSensitivity : (joystickSensitivity * Time.deltaTime);

        float panDelta = lookInput.x * sensitivity;
        float tiltDelta = lookInput.y * sensitivity * (invertY ? 1f : -1f);

        // Apply raw deltas directly to yaw and pitch
        _yaw += panDelta;
        _pitch += tiltDelta;

        // Clamp pitch to prevent flipping upside down
        _pitch = Mathf.Clamp(_pitch, minPitch, maxPitch);

        // Apply the actual rotation to the camera
        transform.eulerAngles = new Vector3(_pitch, _yaw, 0f);
    }
}
