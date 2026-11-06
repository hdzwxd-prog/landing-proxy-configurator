function Get-LandingFindings($Snapshot) {
    $result=[Collections.Generic.List[string]]::new()
    if($Snapshot.systemProxyPort -in @(18484,18485)) {
        $result.Add('系统代理仍指向落地端口；新版不拥有此设置，需要明确处理旧版残留。')
    }
    if($Snapshot.edgePolicyPort -eq 18484) {
        $result.Add('Edge 存在永久落地策略；退出服务不会自动撤销该策略。')
    }
    if($Snapshot.proxyRepresentationsDiffer) {
        $result.Add('Windows 文本代理设置与实际连接配置不一致。')
    }
    foreach($request in $Snapshot.edgeConnectAttempts) {
        if($request.port -eq 18484 -and $request.status -eq '0xC0000236' -and
            $request.pid -in $Snapshot.edgeNetworkPids -and
            18484 -notin $Snapshot.listeningPorts) {
            $result.Add('已确认 Edge 仍连接已关闭的 18484，并被拒绝。检查浏览器缓存策略及后台进程。')
            break
        }
    }
    if($Snapshot.edgeEstablishedPorts -contains 18484) {
        $result.Add('本次快照观察到 Edge 与落地入口的有效连接；这不证明全部请求或未来请求的路径。')
    }
    if($Snapshot.edgeEstablishedPorts -contains 7892 -or $Snapshot.edgeEstablishedPorts -contains 7980) {
        $result.Add('本次快照观察到 Edge 与普通上游的有效连接。')
    }
    if(-not $Snapshot.connectionReadSucceeded) {
        $result.Add('无法读取进程连接；不能判定健康。')
    } elseif(-not $Snapshot.edgeEstablishedPorts.Count -and -not $Snapshot.edgeConnectAttempts.Count) {
        $result.Add('没有 Edge 请求证据；状态未验证，不能据此判定正常或被防火墙拦截。')
    }
    if(18485 -notin $Snapshot.listeningPorts) {
        $result.Add('德国专用入口未监听。未启动 Claude、未访问 Claude，也未解除其保护。')
    }
    return $result.ToArray()
}
