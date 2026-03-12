using System.Collections.Generic;
using UnityEngine;

public class CityGenerator : MonoBehaviour
{
    [Header("City Grid")]
    [Tooltip("Number of city blocks along X and Z")]
    public Vector2Int gridSize = new Vector2Int(3, 3);

    [Tooltip("Size of each city block in world units")]
    public float blockSize = 24f;

    [Tooltip("Width of roads between blocks")]
    public float roadWidth = 8f;

    [Header("Roads")]
    [Tooltip("Road segment prefabs (randomly selected for variety)")]
    public GameObject[] roadPrefabs;

    [Tooltip("Length of one road segment prefab along its forward axis")]
    public float roadSegmentLength = 4f;

    [Header("Building Chunks")]
    [Tooltip("Chunks used for the ground floor (e.g. door pieces)")]
    public GameObject[] groundFloorChunks;

    [Tooltip("Chunks stacked for middle floors (e.g. window pieces)")]
    public GameObject[] floorChunks;

    [Tooltip("Chunks placed on top as the roof")]
    public GameObject[] roofChunks;

    [Header("Building Dimensions")]
    [Tooltip("Vertical distance between each stacked chunk")]
    public float chunkStep = 3f;

    [Tooltip("Horizontal width of each chunk for side-by-side placement")]
    public float chunkWidth = 4f;

    [Tooltip("Minimum number of floor levels per building")]
    public int minHeight = 2;

    [Tooltip("Maximum number of floor levels per building")]
    public int maxHeight = 8;

    [Tooltip("Minimum number of chunks along building length")]
    public int minLength = 1;

    [Tooltip("Maximum number of chunks along building length")]
    public int maxLength = 3;

    [Header("Block Fill")]
    [Tooltip("Building slots per block side (e.g. 3 = up to 9 buildings per block)")]
    public int buildingsPerBlockSide = 3;

    [Tooltip("Margin between buildings and the road edge")]
    public float buildingMargin = 2f;

    [Tooltip("Probability that a building slot gets filled")]
    [Range(0f, 1f)]
    public float buildingDensity = 0.8f;

    [Header("Traffic Paths")]
    [Tooltip("Generate waypoint paths for AI traffic along roads")]
    public bool generateTrafficPaths = true;

    [Tooltip("Distance between waypoints along roads")]
    public float waypointSpacing = 8f;

    [Header("Randomization")]
    public int seed = 42;

    // ------------------------------------------------------------------ //
    //  Public API (called from Editor button)
    // ------------------------------------------------------------------ //

    public void Generate()
    {
        Clear();

        var savedState = Random.state;
        Random.InitState(seed);

        Transform city = CreateChild("Generated City", transform);
        GenerateRoads(city);
        GenerateBuildings(city);
        if (generateTrafficPaths) GenerateTrafficPaths(city);

        Random.state = savedState;
    }

    public void Clear()
    {
        for (int i = transform.childCount - 1; i >= 0; i--)
            DestroyImmediate(transform.GetChild(i).gameObject);
    }

    // ------------------------------------------------------------------ //
    //  Roads
    // ------------------------------------------------------------------ //

    private void GenerateRoads(Transform parent)
    {
        if (roadPrefabs == null || roadPrefabs.Length == 0) return;

        Transform container = CreateChild("Roads", parent);
        float stride = blockSize + roadWidth;
        float cityWidth = gridSize.x * stride + roadWidth;
        float cityDepth = gridSize.y * stride + roadWidth;

        // Horizontal roads (running along X)
        for (int row = 0; row <= gridSize.y; row++)
        {
            float z = row * stride + roadWidth * 0.5f;
            int count = Mathf.CeilToInt(cityWidth / roadSegmentLength);

            for (int i = 0; i < count; i++)
            {
                Vector3 pos = new Vector3(i * roadSegmentLength, 0f, z);
                PlacePrefab(RandomFrom(roadPrefabs), container, pos, Quaternion.identity);
            }
        }

        // Vertical roads (running along Z)
        for (int col = 0; col <= gridSize.x; col++)
        {
            float x = col * stride + roadWidth * 0.5f;
            int count = Mathf.CeilToInt(cityDepth / roadSegmentLength);

            for (int i = 0; i < count; i++)
            {
                Vector3 pos = new Vector3(x, 0f, i * roadSegmentLength);
                PlacePrefab(RandomFrom(roadPrefabs), container, pos, Quaternion.Euler(0f, 90f, 0f));
            }
        }
    }

    // ------------------------------------------------------------------ //
    //  Buildings
    // ------------------------------------------------------------------ //

    private void GenerateBuildings(Transform parent)
    {
        bool hasGround = groundFloorChunks != null && groundFloorChunks.Length > 0;
        bool hasFloor  = floorChunks != null && floorChunks.Length > 0;
        if (!hasGround && !hasFloor) return;

        Transform container = CreateChild("Buildings", parent);
        float stride = blockSize + roadWidth;

        for (int bx = 0; bx < gridSize.x; bx++)
        {
            for (int bz = 0; bz < gridSize.y; bz++)
            {
                float originX = roadWidth + bx * stride;
                float originZ = roadWidth + bz * stride;

                Transform block = CreateChild($"Block_{bx}_{bz}", container);
                FillBlock(block, originX, originZ);
            }
        }
    }

    private void FillBlock(Transform parent, float originX, float originZ)
    {
        float usable = blockSize - 2f * buildingMargin;
        if (usable <= 0f || buildingsPerBlockSide <= 0) return;

        float cell = usable / buildingsPerBlockSide;

        for (int cx = 0; cx < buildingsPerBlockSide; cx++)
        {
            for (int cz = 0; cz < buildingsPerBlockSide; cz++)
            {
                if (Random.value > buildingDensity) continue;

                float x = originX + buildingMargin + (cx + 0.5f) * cell;
                float z = originZ + buildingMargin + (cz + 0.5f) * cell;

                StackBuilding(parent, new Vector3(x, 0f, z));
            }
        }
    }

    private void StackBuilding(Transform parent, Vector3 position)
    {
        int floors = Random.Range(minHeight, maxHeight + 1);
        int length = Random.Range(minLength, maxLength + 1);
        float yaw   = 90f * Random.Range(0, 4);

        Transform building = CreateChild("Building", parent);
        building.localPosition = position;
        building.localRotation = Quaternion.Euler(0f, yaw, 0f);

        float halfLen = (length - 1) * chunkWidth * 0.5f;
        bool hasGround = groundFloorChunks != null && groundFloorChunks.Length > 0;
        bool hasFloor  = floorChunks != null && floorChunks.Length > 0;
        bool hasRoof   = roofChunks != null && roofChunks.Length > 0;

        for (int lx = 0; lx < length; lx++)
        {
            float localX = lx * chunkWidth - halfLen;

            // Ground floor
            if (hasGround)
                PlaceChunk(RandomFrom(groundFloorChunks), building, new Vector3(localX, 0f, 0f));

            // Middle floors
            int startFloor = hasGround ? 1 : 0;
            if (hasFloor)
            {
                for (int f = startFloor; f < floors; f++)
                    PlaceChunk(RandomFrom(floorChunks), building, new Vector3(localX, f * chunkStep, 0f));
            }

            // Roof
            if (hasRoof)
                PlaceChunk(RandomFrom(roofChunks), building, new Vector3(localX, floors * chunkStep, 0f));
        }
    }

    // ------------------------------------------------------------------ //
    //  Traffic Paths
    // ------------------------------------------------------------------ //

    private void GenerateTrafficPaths(Transform parent)
    {
        Transform container = CreateChild("Traffic Paths", parent);
        float stride = blockSize + roadWidth;
        float laneOffset = roadWidth * 0.25f;
        Vector3 worldOffset = transform.position;

        for (int bx = 0; bx < gridSize.x; bx++)
        {
            for (int bz = 0; bz < gridSize.y; bz++)
            {
                float left  = bx * stride + roadWidth * 0.5f;
                float right = (bx + 1) * stride + roadWidth * 0.5f;
                float bottom = bz * stride + roadWidth * 0.5f;
                float top   = (bz + 1) * stride + roadWidth * 0.5f;

                // Clockwise loop with right-hand traffic (offset outward from block)
                Vector3 sw = worldOffset + new Vector3(left  - laneOffset, 0f, bottom - laneOffset);
                Vector3 se = worldOffset + new Vector3(right + laneOffset, 0f, bottom - laneOffset);
                Vector3 ne = worldOffset + new Vector3(right + laneOffset, 0f, top    + laneOffset);
                Vector3 nw = worldOffset + new Vector3(left  - laneOffset, 0f, top    + laneOffset);

                var waypoints = new List<Vector3>();
                AddSegmentPoints(waypoints, sw, se);
                AddSegmentPoints(waypoints, se, ne);
                AddSegmentPoints(waypoints, ne, nw);
                AddSegmentPoints(waypoints, nw, sw);

                var pathObj = new GameObject($"Path_Block_{bx}_{bz}");
                pathObj.transform.SetParent(container);
                pathObj.transform.localPosition = Vector3.zero;
                var path = pathObj.AddComponent<CityTrafficPath>();
                path.waypoints = waypoints.ToArray();
                path.isLoop = true;
            }
        }
    }

    private void AddSegmentPoints(List<Vector3> points, Vector3 from, Vector3 to)
    {
        float distance = Vector3.Distance(from, to);
        int count = Mathf.Max(1, Mathf.RoundToInt(distance / waypointSpacing));

        for (int i = 0; i < count; i++)
        {
            float t = (float)i / count;
            points.Add(Vector3.Lerp(from, to, t));
        }
    }

    // ------------------------------------------------------------------ //
    //  Helpers
    // ------------------------------------------------------------------ //

    private GameObject InstantiatePrefab(GameObject prefab, Transform parent)
    {
#if UNITY_EDITOR
        var instance = (GameObject)UnityEditor.PrefabUtility.InstantiatePrefab(prefab, parent);
        if (instance != null) return instance;
#endif
        return Instantiate(prefab, parent);
    }

    private void PlacePrefab(GameObject prefab, Transform parent, Vector3 localPos, Quaternion localRot)
    {
        GameObject go = InstantiatePrefab(prefab, parent);
        go.transform.localPosition = localPos;
        go.transform.localRotation = localRot;
    }

    private void PlaceChunk(GameObject prefab, Transform parent, Vector3 localPos)
    {
        GameObject go = InstantiatePrefab(prefab, parent);
        go.transform.localPosition = localPos;
        go.transform.localRotation = Quaternion.identity;
        EnsureColliders(go);
    }

    private static void EnsureColliders(GameObject root)
    {
        foreach (var filter in root.GetComponentsInChildren<MeshFilter>())
        {
            if (filter.GetComponent<Collider>() == null)
                filter.gameObject.AddComponent<MeshCollider>();
        }
    }

    private Transform CreateChild(string name, Transform parent)
    {
        var go = new GameObject(name);
        go.transform.SetParent(parent);
        go.transform.localPosition = Vector3.zero;
        go.transform.localRotation = Quaternion.identity;
        return go.transform;
    }

    private static T RandomFrom<T>(T[] array) => array[Random.Range(0, array.Length)];
}
