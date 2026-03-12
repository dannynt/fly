using UnityEngine;
using System.Collections.Generic;

/// <summary>
/// Spawns and manages police cars based on the player's WantedLevel.
/// More stars = more police cars chasing.
/// When heat is cleared, all police cars are told to return and despawn.
/// </summary>
public class PoliceDispatcher : MonoBehaviour
{
    [Header("References")]
    [Tooltip("The player's WantedLevel component")]
    public WantedLevel wantedLevel;

    [Header("Police Car")]
    [Tooltip("Prefab for police cars (needs Rigidbody + Collider; PoliceCarController is added automatically)")]
    public GameObject policePrefab;

    [Header("Spawning")]
    [Tooltip("Maximum police cars active at once")]
    public int maxPoliceCars = 5;
    [Tooltip("Seconds between spawning additional police cars when needed")]
    public float spawnInterval = 6f;
    [Tooltip("How far behind/around the player police spawn")]
    public float spawnDistance = 60f;
    [Tooltip("Height at which police cars spawn")]
    public float spawnHeight = 12f;

    [Header("Police per Star")]
    [Tooltip("Number of police cars per wanted star (e.g. 1 star = 1 car, 3 stars = 3 cars)")]
    public int carsPerStar = 1;

    private readonly List<PoliceCarController> activeCars = new List<PoliceCarController>();
    private float spawnTimer;
    private Transform playerTransform;

    void Start()
    {
        if (wantedLevel == null)
        {
            wantedLevel = FindAnyObjectByType<WantedLevel>();
        }
        if (wantedLevel != null)
        {
            playerTransform = wantedLevel.transform;
            wantedLevel.OnHeatCleared += OnHeatCleared;
        }
    }

    void OnDestroy()
    {
        if (wantedLevel != null)
            wantedLevel.OnHeatCleared -= OnHeatCleared;
    }

    void Update()
    {
        if (wantedLevel == null || policePrefab == null) return;

        // Clean up destroyed entries
        activeCars.RemoveAll(c => c == null);

        if (!wantedLevel.IsWanted)
            return;

        int desiredCount = Mathf.Min(wantedLevel.Stars * carsPerStar, maxPoliceCars);

        if (activeCars.Count < desiredCount)
        {
            spawnTimer -= Time.deltaTime;
            if (spawnTimer <= 0f)
            {
                SpawnPoliceCar();
                spawnTimer = spawnInterval;
            }
        }
    }

    private void SpawnPoliceCar()
    {
        if (playerTransform == null) return;

        // Spawn at a random position around the player, outside their view
        Vector2 circle = Random.insideUnitCircle.normalized;
        Vector3 offset = new Vector3(circle.x, 0f, circle.y) * spawnDistance;
        Vector3 spawnPos = playerTransform.position + offset;
        spawnPos.y = spawnHeight;

        // Face toward the player
        Vector3 dir = playerTransform.position - spawnPos;
        dir.y = 0f;
        Quaternion spawnRot = dir.sqrMagnitude > 0.01f ? Quaternion.LookRotation(dir) : Quaternion.identity;

        GameObject car = Instantiate(policePrefab, spawnPos, spawnRot);
        car.name = $"PoliceCar_{activeCars.Count}";

        // Ensure rigidbody
        Rigidbody rb = car.GetComponent<Rigidbody>();
        if (rb == null) rb = car.AddComponent<Rigidbody>();
        rb.mass = 800f;

        PoliceCarController controller = car.GetComponent<PoliceCarController>();
        if (controller == null) controller = car.AddComponent<PoliceCarController>();

        controller.BeginChase(playerTransform);
        activeCars.Add(controller);
    }

    private void OnHeatCleared()
    {
        // Tell all police cars to stop chasing and return
        foreach (var car in activeCars)
        {
            if (car != null)
                car.StopChase();
        }
        activeCars.Clear();
    }
}
