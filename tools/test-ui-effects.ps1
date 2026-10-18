[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source = @('HudLayoutInset','TransparentEffectCompatibility') | ForEach-Object {
    (Get-Content (Join-Path $root "src/QVVR/$_.cs") -Raw).Replace('using System;', '').Replace('using System.Collections.Generic;', '').Replace('using UnityEngine;', '')
}
$fixture=@'
namespace UnityEngine {
 public class Object {
  public bool Destroyed;
  public static bool operator==(Object a,Object b){bool an=object.ReferenceEquals(a,null)||a.Destroyed,bn=object.ReferenceEquals(b,null)||b.Destroyed;return an||bn?an==bn:object.ReferenceEquals(a,b);}
  public static bool operator!=(Object a,Object b){return !(a==b);}public override bool Equals(object v){return object.ReferenceEquals(this,v);}public override int GetHashCode(){return base.GetHashCode();}
 }
 public struct Vector2 {
  public float x,y;public Vector2(float x,float y){this.x=x;this.y=y;}
  public static bool operator==(Vector2 a,Vector2 b){return a.x==b.x&&a.y==b.y;}public static bool operator!=(Vector2 a,Vector2 b){return !(a==b);}
  public override bool Equals(object v){return v is Vector2&&this==(Vector2)v;}public override int GetHashCode(){return x.GetHashCode()^y.GetHashCode();}
 }
 public class Transform:Object {public Transform parent;public readonly List<Transform> Children=new List<Transform>();public int childCount{get{return Children.Count;}}public Transform GetChild(int i){return Children[i];}}
 public class RectTransform:Transform {public Vector2 anchorMin,anchorMax,anchoredPosition,sizeDelta;}
 public class Canvas:Object {public Transform transform=new Transform();}
 public struct Scene {public bool Valid,isLoaded;public bool IsValid(){return Valid;}}
 public class GameObject {public Scene scene;}
 public class Shader {public string name;public static int PropertyToID(string name){return name=="_SrcBlend"?1:2;}}
 public class Material:Object {public string name;public Shader shader;public float Src=1,Dst=0,Alpha=.5f;public bool Fail;public float GetFloat(int id){return id==1?Src:Dst;}public void SetFloat(int id,float value){if(Fail&&id==2&&value==10)throw new InvalidOperationException();if(id==1)Src=value;else Dst=value;}}
 public class Renderer:Object {public GameObject gameObject=new GameObject{scene=new Scene{Valid=true,isLoaded=true}};public Material[] sharedMaterials;}
 public static class Resources {public static Renderer[] Snapshot;public static T[] FindObjectsOfTypeAll<T>(){return (T[])(object)Snapshot;}}
}
namespace QVVR {
 public static class UiEffectTests {
  static int checks;static void Check(bool ok,string text){checks++;if(!ok)throw new Exception(text);}static bool Near(float a,float b){return Math.Abs(a-b)<.00001f;}
  public static int Run(){
   var canvas=new Canvas();var corner=new RectTransform{parent=canvas.transform,anchorMin=new Vector2(1,1),anchorMax=new Vector2(1,1),sizeDelta=new Vector2(100,100),anchoredPosition=new Vector2(-40,-20)};
   var panel=new RectTransform{parent=canvas.transform,anchorMin=new Vector2(0,0),anchorMax=new Vector2(1,1)};
   var centered=new RectTransform{parent=canvas.transform,anchorMin=new Vector2(.5f,.5f),anchorMax=new Vector2(.5f,.5f)};
   var nested=new RectTransform{parent=panel,anchorMin=new Vector2(1,1),anchorMax=new Vector2(1,1)};panel.Children.Add(nested);
   canvas.transform.Children.Add(corner);canvas.transform.Children.Add(panel);canvas.transform.Children.Add(centered);
   var inset=new HudLayoutInset();inset.Apply(canvas,12);
   Check(Near(corner.anchorMin.x,.88f)&&Near(corner.anchorMin.y,.88f),"Corner UI moves toward center.");
   Check(Near(panel.anchorMin.x,.12f)&&Near(panel.anchorMax.x,.88f),"Stretch panel edges move inward.");
   Check(centered.anchorMin==new Vector2(.5f,.5f),"Centered UI stays centered.");
   Check(corner.sizeDelta==new Vector2(100,100)&&corner.anchoredPosition==new Vector2(-40,-20),"Never scale fonts/widgets or overwrite their game offsets.");
   Check(nested.anchorMin==new Vector2(1,1),"Only root layout changes; nested anchors are not inset twice.");
   inset.Apply(canvas,12);Check(Near(corner.anchorMin.x,.88f),"Repeated scans do not compound inset.");
   inset.Apply(canvas,20);Check(Near(corner.anchorMin.x,.8f),"Live setting uses original anchors.");
   corner.anchorMin=new Vector2(.8f,.4f);inset.Apply(canvas,12);inset.Clear();
   Check(corner.anchorMin==new Vector2(.8f,.4f)&&corner.anchorMax==new Vector2(1,1),"Preserve game-side anchor updates when restoring.");
   Check(panel.anchorMin==new Vector2(0,0)&&panel.anchorMax==new Vector2(1,1),"Clear restores original stretch layout.");
   inset.Apply(canvas,12);inset.Apply(canvas,0);Check(panel.anchorMin==new Vector2(0,0),"Zero restores flat/title layout.");
   Check(HudLayoutMath.Percent(float.NaN)==12&&HudLayoutMath.Percent(100)==45&&HudLayoutMath.Percent(-1)==0,"Inset bounds/invalid settings safe.");
   inset.Apply(canvas,36);Check(Near(panel.anchorMin.x,.36f)&&Near(panel.anchorMax.x,.64f),"Allow inward centering beyond the old 25 percent limit.");
   inset.Apply(canvas,45);Check(Near(panel.anchorMin.x,.45f)&&Near(panel.anchorMax.x,.55f)&&panel.anchorMin.x<panel.anchorMax.x,"Maximum inset never collapses/inverts the layout.");
   inset.Apply(canvas,12);canvas.transform.Children.Remove(panel);panel.parent=new Transform();inset.Apply(canvas,12);
   Check(panel.anchorMin==new Vector2(0,0),"Reparented root layout restored.");inset.Clear();
   var fairy=new Material{name="FairyMaterial",shader=new Shader{name="Custom/2SideShader"}};
   var other=new Material{name="Other",shader=fairy.shader};var prefab=new Material{name="FairyMaterial",shader=fairy.shader};
   Resources.Snapshot=new[]{new Renderer{sharedMaterials=new[]{fairy,other}},new Renderer{sharedMaterials=new[]{fairy}},new Renderer{sharedMaterials=new[]{prefab},gameObject=new GameObject{scene=new Scene()}}};
   var effects=new TransparentEffectCompatibility();effects.Refresh();Check(effects.Count==1,"Cache only exact loaded fairy material, deduplicated.");
   Check(!TransparentEffectCompatibility.Matches("FairyMaterial","Other")&&!TransparentEffectCompatibility.Matches("Other","Custom/2SideShader"),"No broad shader/material edits.");
   effects.Prepare();effects.Prepare();Check(fairy.Src==5&&fairy.Dst==10,"VR uses straight-alpha blend, not opaque quad coverage.");
   Check(other.Src==1&&prefab.Src==1&&fairy.Alpha==.5f,"Other materials, prefabs and alpha values unchanged.");
   effects.Restore();Check(fairy.Src==1&&fairy.Dst==0,"Nested calls restore live original blend.");
   fairy.Dst=10;effects.Prepare();effects.Restore();Check(fairy.Src==1&&fairy.Dst==10,"Existing game-controlled transparent blend retained.");
   fairy.Dst=0;fairy.Fail=true;bool failed=false;try{effects.Prepare();}catch(InvalidOperationException){failed=true;}finally{effects.Restore();}
   Check(failed&&fairy.Src==1&&fairy.Dst==0,"Partial setup exception restores original material.");fairy.Fail=false;
   effects.Prepare();effects.Clear();Check(fairy.Src==1&&effects.Count==0,"Scene/shutdown cleanup restores and clears cache.");
   return checks;
  }
 }
}
'@
Add-Type -TypeDefinition ("using System;using System.Collections.Generic;using UnityEngine;`n"+($source -join "`n")+$fixture)
$checks=[QVVR.UiEffectTests]::Run()
Write-Host "UI inset / transparent effect compatibility: $checks assertions passed; no game/VR session started."
