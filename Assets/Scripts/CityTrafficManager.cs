using UnityEngine;

public class CityTrafficManager : MonoBehaviour
{
    [Header("Car Prefabs")]
    [Tooltip("Add car prefabs here. They will be randomly selected and spawned as AI traffic.")]
    public GameObject[] carPrefabs;

    [Header("Spawning")]
    [Tooltip("Total number of AI cars to spawn in the city")]
    public int numberOfCars = 20;

    [Header("Flight Settings")]
    [Tooltip("Base flying height for the AI cars")]
    public float flyHeight = 8f;
    [Tooltip("Random height variation added to base height")]
    public float heightVariation = 3f;

    [Header("Speed Settings")]
    [Tooltip("Minimum max speed for AI cars")]
    public float minSpeed = 15f;
    [Tooltip("Maximum max speed for AI cars")]
    public float maxSpeed = 30f;

    private Transform carContainer;

    void Start()
    {
        SpawnCars();
    }

    public void SpawnCars()
    {
        if (carPrefabs == null || carPrefabs.Length == 0)
        {
            Debug.LogWarning("CityTrafficManager: No car prefabs assigned.");
            return;
        }

        var paths = FindObjectsByType<CityTrafficPath>(FindObjectsSortMode.None);
        if (paths.Length == 0)
        {
            Debug.LogWarning("CityTrafficManager: No CityTrafficPath found. Generate the city first.");
            return;
        }

        carContainer = new GameObject("AI Traffic Cars").transform;
        carContainer.SetParent(transform);

        for (int i = 0; i < numberOfCars; i++)
        {
            CityTrafficPath path = paths[i % paths.Length];
            if (path.waypoints == null || path.waypoints.Length < 2) continue;

            GameObject prefab = carPrefabs[Random.Range(0, carPrefabs.Length)];
            int startIndex = Random.Range(0, path.waypoints.Length);

            float carHeight = flyHeight + Random.Range(0f, heightVariation);
            Vector3 spawnPos = path.waypoints[startIndex];
            spawnPos.y = carHeight;

            // Face toward next waypoint
            int nextIndex = (startIndex + 1) % path.waypoints.Length;
            Vector3 dir = path.waypoints[nextIndex] - path.waypoints[startIndex];
            dir.y = 0f;
            Quaternion spawnRot = dir.sqrMagnitude > 0.01f ? Quaternion.LookRotation(dir) : Quaternion.identity;

            GameObject car = Instantiate(prefab, spawnPos, spawnRot, carContainer);
            car.name = $"AICar_{i}";

            AIFlyingCarController ai = car.GetComponent<AIFlyingCarController>();
            if (ai == null) ai = car.AddComponent<AIFlyingCarController>();

            ai.waypoints = path.waypoints;
            ai.isLoop = path.isLoop;
            ai.currentWaypointIndex = (startIndex + 1) % path.waypoints.Length;
            ai.flyHeight = carHeight;
            ai.maxSpeed = Random.Range(minSpeed, maxSpeed);
        }
    }
}
