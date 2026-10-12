[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$rules = Get-Content -LiteralPath (Join-Path $root 'src/QVVR/CloudVisualRules.cs') -Raw
$filter = Get-Content -LiteralPath (Join-Path $root 'src/QVVR/CloudRendererFilter.cs') -Raw
$tests = @'
// Headless Unity API doubles. Tests execute the real filter source, not a
// parallel implementation, without launching QV or invoking Unity native code.
namespace UnityEngine {
    public class Object {
        public bool Destroyed;
        public static bool operator ==(Object a, Object b) {
            bool an=object.ReferenceEquals(a,null) || a.Destroyed;
            bool bn=object.ReferenceEquals(b,null) || b.Destroyed;
            return an || bn ? an==bn : object.ReferenceEquals(a,b);
        }
        public static bool operator !=(Object a,Object b) { return !(a==b); }
        public override bool Equals(object o) { return object.ReferenceEquals(this,o); }
        public override int GetHashCode() { return base.GetHashCode(); }
    }
    public struct Scene { public bool Valid,isLoaded; public bool IsValid(){return Valid;} }
    public class GameObject { public string name; public Scene scene; public bool Active=true; }
    public class Shader { public string name; }
    public class Material { public string name; public Shader shader; }
    public class Renderer : Object {
        public GameObject gameObject; public Material[] sharedMaterials;
        public bool ThrowOnDisable; private bool state=true;
        public bool enabled { get{return state;} set{if (!value && ThrowOnDisable) throw new System.InvalidOperationException("mock disable failure"); state=value;} }
    }
    public static class Resources {
        public static Renderer[] Snapshot;
        public static T[] FindObjectsOfTypeAll<T>() { return (T[])(object)Snapshot; }
    }
}
namespace QVVR {
    public static class CloudFilterTests {
        private static int checks;
        private static void Assert(bool value,string message) { checks++; if(!value) throw new System.Exception(message); }
        private static UnityEngine.Renderer Make(string obj,string mat,string shader) {
            return new UnityEngine.Renderer {
                gameObject=new UnityEngine.GameObject { name=obj,scene=new UnityEngine.Scene{Valid=true,isLoaded=true} },
                sharedMaterials=new[]{new UnityEngine.Material{name=mat,shader=new UnityEngine.Shader{name=shader}}}
            };
        }
        public static int Run() {
            const string glow="ERB/Particles/Add_CenterGlow", shadowShader="Hidden/ScreenSpaceCloudShadow";
            Assert(CloudVisualRules.Hide("Clouds","Cloud",glow),"Verified decorative mesh must match.");
            Assert(CloudVisualRules.Hide("Clouds(Clone)","Cloud (Instance)",glow),"Instanced decorative names must match.");
            Assert(CloudVisualRules.Hide("Plane","ScreenSpaceCloudShadow",shadowShader),"Verified cloud shadow shader must match.");
            Assert(!CloudVisualRules.Hide("Clouds","Unrelated",glow),"Do not hide arbitrary glow effects.");
            Assert(!CloudVisualRules.Hide("Cloud","Cloud",glow),"Do not broadly match every object called Cloud.");
            Assert(!CloudVisualRules.Hide("CloudRain","RainCloud","RainCloud/RainCloud"),"Rain gameplay must survive.");
            Assert(!CloudVisualRules.Hide("Cloud","CFXM2_SingleSmoke AB","Mobile/Particles/Alpha Blended"),"Player cloud particle must survive.");
            Assert(!CloudVisualRules.Hide("UI_Cloud","CloudSave","UI/Default"),"Cloud-save UI must survive.");
            Assert(!CloudVisualRules.Hide("CloudsBuilding","Cloud",glow),"Prefix matches must not hide buildings.");
            Assert(!CloudVisualRules.Hide(null,null,null),"Missing metadata must not match.");
            var decor=Make("Clouds","Cloud",glow);
            var shadow=Make("Shadow","ScreenSpaceCloudShadow",shadowShader); shadow.enabled=false;
            var rain=Make("CloudRain","RainCloud","RainCloud/RainCloud");
            var ui=Make("UI_Cloud","CloudSave","UI/Default");
            var prefab=Make("Clouds","Cloud",glow); prefab.gameObject.scene=new UnityEngine.Scene{Valid=false,isLoaded=false};
            var unloaded=Make("Clouds","Cloud",glow); unloaded.gameObject.scene=new UnityEngine.Scene{Valid=true,isLoaded=false};
            var mixed=Make("Clouds","Cloud",glow); mixed.sharedMaterials=new[]{mixed.sharedMaterials[0],new UnityEngine.Material{name="Stone",shader=new UnityEngine.Shader{name="Standard"}}};
            var missing=Make("Clouds","Cloud",glow); missing.sharedMaterials=new UnityEngine.Material[]{null};
            UnityEngine.Resources.Snapshot=new[]{decor,shadow,rain,ui,prefab,unloaded,mixed,missing};
            var filter=new CloudRendererFilter(); filter.Refresh();
            Assert(filter.Count==2,"Cache only loaded decorative cloud renderers, not mixed geometry/prefabs.");
            filter.HideForStereo();
            Assert(!decor.enabled && !shadow.enabled,"Stereo must hide both decorative renderers.");
            Assert(rain.enabled && ui.enabled && prefab.enabled && unloaded.enabled && mixed.enabled && missing.enabled,"Other renderers must stay untouched.");
            Assert(decor.gameObject.Active && rain.gameObject.Active,"Never deactivate game objects or gameplay scripts.");
            filter.HideForStereo(); filter.Restore();
            Assert(decor.enabled && !shadow.enabled,"Nested hide must retain ORIGINAL enabled/disabled states.");
            decor.enabled=false; filter.HideForStereo(); filter.Restore();
            Assert(!decor.enabled,"A later game-side disabled state must not be forced on.");
            decor.enabled=true; filter.HideForStereo(); filter.Clear();
            Assert(decor.enabled && filter.Count==0,"Scene change/shutdown must restore and clear cache.");
            filter.Refresh(); decor.Destroyed=true; filter.HideForStereo(); filter.Restore();
            Assert(!shadow.enabled,"Destroyed renderer must not prevent restoration of others.");
            decor.Destroyed=false; shadow.enabled=true; filter.Refresh(); shadow.ThrowOnDisable=true;
            bool failed=false;
            try { filter.HideForStereo(); } catch(System.InvalidOperationException) { failed=true; } finally { filter.Restore(); }
            Assert(failed && decor.enabled && shadow.enabled,"Finally must restore partial suppression when render setup fails.");
            shadow.ThrowOnDisable=false; filter.Clear();
            return checks;
        }
    }
}
'@
$source = "using System;`nusing System.Collections.Generic;`nusing UnityEngine;`n" +
    $rules.Replace('using System;', '') +
    $filter.Replace('using System.Collections.Generic;', '').Replace('using UnityEngine;', '') + $tests
Add-Type -TypeDefinition $source
$count = [QVVR.CloudFilterTests]::Run()
Write-Host "Cloud filtering: $count assertions passed; no game or Unity session started."
