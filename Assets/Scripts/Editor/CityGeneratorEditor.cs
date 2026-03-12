using UnityEditor;
using UnityEngine;

[CustomEditor(typeof(CityGenerator))]
public class CityGeneratorEditor : Editor
{
    public override void OnInspectorGUI()
    {
        DrawDefaultInspector();

        CityGenerator generator = (CityGenerator)target;

        EditorGUILayout.Space(10);

        using (new EditorGUILayout.HorizontalScope())
        {
            if (GUILayout.Button("Generate City", GUILayout.Height(30)))
            {
                Undo.RegisterFullObjectHierarchyUndo(generator.gameObject, "Generate City");
                generator.Generate();
            }

            if (GUILayout.Button("Clear City", GUILayout.Height(30)))
            {
                Undo.RegisterFullObjectHierarchyUndo(generator.gameObject, "Clear City");
                generator.Clear();
            }
        }

        if (GUILayout.Button("Randomize Seed"))
        {
            Undo.RecordObject(generator, "Randomize Seed");
            generator.seed = Random.Range(0, int.MaxValue);
        }
    }
}
