using UnityEngine;

public class CityTrafficPath : MonoBehaviour
{
    [HideInInspector] public Vector3[] waypoints;
    [HideInInspector] public bool isLoop = true;

    private void OnDrawGizmosSelected()
    {
        if (waypoints == null || waypoints.Length < 2) return;

        Gizmos.color = Color.cyan;
        for (int i = 0; i < waypoints.Length; i++)
        {
            Gizmos.DrawSphere(waypoints[i], 0.4f);

            int next = (i + 1) % waypoints.Length;
            if (!isLoop && next == 0) continue;
            Gizmos.DrawLine(waypoints[i], waypoints[next]);
        }
    }
}
