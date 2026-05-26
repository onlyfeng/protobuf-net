
using System.Runtime.CompilerServices;

#if !NETSTANDARD2_0_OR_GREATER && !UNITY_2022_3_OR_NEWER // see #1214; omit under Unity 2022.3+ where SkipLocalsInitAttribute isn't usable (it's a perf-only optimization, so skipping it is safe)
[module: SkipLocalsInit]
#endif