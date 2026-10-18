// API doubles for pure production policies; never loads Unity or starts QV.
namespace UnityEngine.Events { public delegate void UnityAction(); }
namespace UnityEngine {
 public struct Vector3 {
  public float x,y,z; public Vector3(float a,float b,float c){x=a;y=b;z=c;}
  public static Vector3 operator-(Vector3 a,Vector3 b){return new Vector3(a.x-b.x,a.y-b.y,a.z-b.z);}
  public static Vector3 operator+(Vector3 a,Vector3 b){return new Vector3(a.x+b.x,a.y+b.y,a.z+b.z);}
  public static Vector3 operator*(Vector3 a,float b){return new Vector3(a.x*b,a.y*b,a.z*b);}
  public static bool operator==(Vector3 a,Vector3 b){return a.x==b.x&&a.y==b.y&&a.z==b.z;}
  public static bool operator!=(Vector3 a,Vector3 b){return !(a==b);}
  public override bool Equals(object o){return o is Vector3&&(Vector3)o==this;}public override int GetHashCode(){return x.GetHashCode();}
 }
 public struct Quaternion {
  public float w;public static bool operator==(Quaternion a,Quaternion b){return a.w==b.w;}
  public static bool operator!=(Quaternion a,Quaternion b){return !(a==b);}
  public override bool Equals(object o){return o is Quaternion&&(Quaternion)o==this;}public override int GetHashCode(){return w.GetHashCode();}
 }
 public struct Rect {
  public float width,height;public static bool operator==(Rect a,Rect b){return a.width==b.width&&a.height==b.height;}
  public static bool operator!=(Rect a,Rect b){return !(a==b);}
  public override bool Equals(object o){return o is Rect&&(Rect)o==this;}public override int GetHashCode(){return width.GetHashCode();}
 }
 public struct Bounds {
  public Vector3 center,extents;public Bounds(Vector3 c,Vector3 size){center=c;extents=size*.5f;}
  public Vector3 min{get{return center-extents;}}public Vector3 max{get{return center+extents;}}
  public void Encapsulate(Bounds b){Vector3 lo=min,hi=max;lo=new Vector3(System.Math.Min(lo.x,b.min.x),System.Math.Min(lo.y,b.min.y),System.Math.Min(lo.z,b.min.z));hi=new Vector3(System.Math.Max(hi.x,b.max.x),System.Math.Max(hi.y,b.max.y),System.Math.Max(hi.z,b.max.z));center=(lo+hi)*.5f;extents=(hi-lo)*.5f;}
 }
 public struct Matrix4x4 {
  float[] values;public static Matrix4x4 identity{get{var m=new Matrix4x4{values=new float[16]};for(int i=0;i<4;i++)m[i,i]=1;return m;}}
  public float this[int r,int c]{get{return values==null?0:values[r*4+c];}set{values[r*4+c]=value;}}
  public static Matrix4x4 operator*(Matrix4x4 a,Matrix4x4 b){var m=new Matrix4x4{values=new float[16]};for(int r=0;r<4;r++)for(int c=0;c<4;c++)for(int k=0;k<4;k++)m[r,c]+=a[r,k]*b[k,c];return m;}
 }
 public static class Mathf {public static float Max(float a,float b){return System.Math.Max(a,b);}public static float Abs(float a){return System.Math.Abs(a);}}
 public struct Scene {public bool Valid,isLoaded;public bool IsValid(){return Valid;}}
 public class GameObject {public Scene scene=new Scene{Valid=true,isLoaded=true};public bool activeInHierarchy=true;public int layer;}
 public class Shader {public string name;}
 public class Material {public Shader shader;public int renderQueue=2000;}
 public class Renderer {public GameObject gameObject=new GameObject();public Material[] sharedMaterials=new Material[0];public bool enabled=true;public Bounds bounds;}
 public class Mesh {public System.IntPtr Buffer;public System.IntPtr GetNativeIndexBufferPtr(){return Buffer;}}
 public class MeshFilter {public Mesh sharedMesh;}
 public class MeshRenderer:Renderer {public bool isPartOfStaticBatch;public MeshFilter Filter;public T GetComponent<T>()where T:class{return Filter as T;}}
 public class Camera {public int cullingMask=-1;public Matrix4x4 projectionMatrix=Matrix4x4.identity,worldToCameraMatrix=Matrix4x4.identity;}
 public static class Resources {
  public static Renderer[] Snapshot=new Renderer[0];
  public static T[] FindObjectsOfTypeAll<T>(){var list=new System.Collections.Generic.List<T>();foreach(var r in Snapshot)if(r is T)list.Add((T)(object)r);return list.ToArray();}
 }
 public class Transform {
  public Transform parent;public GameObject gameObject=new GameObject();public Vector3 localPosition,localScale;public Quaternion localRotation;
  public CanvasGroup ParentGroup;public Animator ParentAnimator;
  public T GetComponent<T>()where T:class{return typeof(T)==typeof(CanvasGroup)?ParentGroup as T:ParentAnimator as T;}
 }
 public class RectTransform:Transform {public Rect rect;}
 public class CanvasGroup {public float alpha=1;public bool enabled=true,ignoreParentGroups;}
 public class Animator {public bool enabled=true;public GameObject gameObject=new GameObject();public float speed=1;}
 public class Canvas {
  public bool enabled=true;public Transform transform=new Transform();public object[] Children=new object[0];
  public void GetComponentsInChildren<T>(bool inactive,System.Collections.Generic.List<T> results){results.Clear();if(this is T)results.Add((T)(object)this);foreach(var item in Children)if(item is T)results.Add((T)item);}
 }
}
namespace UnityEngine.UI {
 public class Graphic {
  public bool enabled=true;public virtual UnityEngine.Material material{get;set;}public virtual UnityEngine.Material defaultMaterial{get;set;}
  UnityEngine.Events.UnityAction vertices,materials,layout;
  public int Listeners;
  public void RegisterDirtyVerticesCallback(UnityEngine.Events.UnityAction a){vertices+=a;Listeners++;}
  public void RegisterDirtyMaterialCallback(UnityEngine.Events.UnityAction a){materials+=a;Listeners++;}
  public void RegisterDirtyLayoutCallback(UnityEngine.Events.UnityAction a){layout+=a;Listeners++;}
  public void UnregisterDirtyVerticesCallback(UnityEngine.Events.UnityAction a){vertices-=a;Listeners--;}
  public void UnregisterDirtyMaterialCallback(UnityEngine.Events.UnityAction a){materials-=a;Listeners--;}
  public void UnregisterDirtyLayoutCallback(UnityEngine.Events.UnityAction a){layout-=a;Listeners--;}
  public void Dirty(int kind){var a=kind==0?vertices:kind==1?materials:layout;if(a!=null)a();}
 }
 public class Image:Graphic {}
 public class RawImage:Graphic {}
 public class Text:Graphic {}
 public class UninitializedSubMesh:Graphic {
  public int MaterialReads;
  public override UnityEngine.Material material{get{MaterialReads++;throw new System.ArgumentNullException("source");}set{throw new System.InvalidOperationException("Do not mutate materials");}}
  public override UnityEngine.Material defaultMaterial{get{MaterialReads++;throw new System.InvalidOperationException("Unsupported virtual getter");}set{}}
 }
}
