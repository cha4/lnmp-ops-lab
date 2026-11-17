<%@ page contentType="text/html;charset=UTF-8" pageEncoding="UTF-8" %>
<html>
<head><meta charset="utf-8"><title>商品库存查询</title></head>
<body style="font-family:sans-serif;padding:30px">
<h1>商品库存查询服务</h1>
<p>服务节点：<b><%= java.net.InetAddress.getLocalHost().getHostName() %></b></p>
<p>响应时间：<%= new java.util.Date() %></p>
<table border="1" cellpadding="8" style="border-collapse:collapse">
<tr><th>商品编码</th><th>商品名称</th><th>库位</th><th>库存</th></tr>
<tr><td>SKU001</td><td>测试商品A</td><td>A-01-03</td><td>128</td></tr>
<tr><td>SKU002</td><td>测试商品B</td><td>A-02-11</td><td>64</td></tr>
<tr><td>SKU003</td><td>测试商品C</td><td>B-01-05</td><td>256</td></tr>
</table>
</body>
</html>
