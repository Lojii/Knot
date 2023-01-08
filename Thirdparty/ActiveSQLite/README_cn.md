# ActiveSQLite

[![Version](https://img.shields.io/cocoapods/v/ActiveSQLite.svg?style=flat)](http://cocoapods.org/pods/ActiveSQLite)
<!--[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/Carthage/Carthage)-->
[![License](https://img.shields.io/cocoapods/l/ActiveSQLite.svg?style=flat)](http://cocoapods.org/pods/ActiveSQLite)
[![Platform](https://img.shields.io/cocoapods/p/ActiveSQLite.svg?style=flat)](http://cocoapods.org/pods/ActiveSQLite)


ActiveSQLite 是一个 [SQLite.Swift](https://github.com/stephencelis/SQLite.swift) 的封装和扩展。 目的是让你使用SQLite.swift更加简单。<p>
使用ActiveSQLite的一个例子是[Reed downloader](https://github.com/KevinZhouRafael/Reed)。

[**English Version**](README.md)

## 特性

 - [x] 支持 SQLite.swift 的所有特性。
 - [x] 自动创建表. 自动创建 id , created\_at 和 updated\_at 列。
 - [x] 自动把SQL查询的数据赋值给数据库模型ASModel的属性。 
 - [x] 自定义表名和模型名之间的映射，列名和模型的属性名之间的映射。
 - [x] 支持事务和异步。
 - [x] 提供可扩展，链式，延迟执行的查询接口。
 - [x] 通过属性名字符串，字典，或SQLite.swift的表达式Expression<T>查询和修改数据。
 - [x] 日志级别
 - [ ] 由Runtime编码改为Codable编码
 - [ ] 完全的面向协议编程
 - [ ] 表关联
 - [ ] 缓存和惰值


## 例子

执行 ActiveSQLiteTests target.


## 用法

```swift
import ActiveSQLite

//定义model和table
class Product:ASModel{
    var name:String = ""
    var price:NSNumber = NSNumber(value:0.0)
    var desc:String?
    var publish_date:NSDate?
}

//保存
let product = Product()
product.name = "iPhone 7"
product.price = NSNumber(value:599)
try! product.save()

//查询
let p = Product.findFirst("name",value:"iPhone")

//or 
let name = Expression<String>("name")
let p = Product.findAll(name == "iPhone").first                    
//id = 1, name = iPhone 7, price = 599, desc = nil,  publish_date = nil, created_at = 1498616987587.237, updated_at = 1498616987587.237, 

//更新
p.name = "iPad"
try! p.update()

//删除
p.delete()

```

## 开始

在你的工程的target使用ActiveSQLite, 需要首先导入 `ActiveSQLite` 模块.

``` swift
import ActiveSQLite
```


### 连接数据库

``` swift
ASConfigration.setDefaultDB(path:"db file path", name: "default db name")

//If you want a other db
ASConfigration.setDB(path: "other db file path", name: "other db name")

```
必须设置 setDefaultDB 。

## 支持的数据类型

| ActiveSQLite<br />Swift Type    | SQLite.swift<br />Swift Type    | SQLite<br /> SQLite Type      | 表字段默认值<br /> 模型属性不用可选类型的情况下 |
| --------------- | --------------- | ----------- | ---------- |
| `NSNumber `     | `Int64`         | `INTEGER`   | `0`|
| `NSNumber `     | `Double`        | `REAL`      |`0.0`|
| `String`        | `String`        | `TEXT`      |`""`|
| `nil`           | `nil`           | `NULL`      |`NULL`|
|                 | `SQLite.Blob`   | `BLOB`      ||
| `NSDate`        | `Int64`         | `INTEGER`   |`0`|



NSNumber类型对应SQLite.swift的两种类型（Int64和Double)。NSNumber默认的映射类型是Int64。重写ASModel的doubleTypes()方法能标记属性为Double类型。

``` swift
class Product:ASModel{

    var name:String = ""
    var price:NSNumber = NSNumber(value:0.0)
    var desc:String?
    var publish_date:NSDate?

  override func doubleTypes() -> [String]{
      return ["price"]
  }
  
}

```
ActiviteSQLite映射NSDate类型到SQLite.swift的Int64类型。 你可以通过查找SQLite.swift的文档[Custom Types of Documentaion](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#custom-types)映射NSDate到String。


## 创建表

ActiveSQLite自动创建表并且添加"id", "created\_at"和 "updated\_at"字段。"id"字段是主键。 创建的代码类似于下面这样:

``` swift
try db.run(products.create { t in      
    t.column(id, primaryKey: true)
    t.column(Expression<NSDate>("created_at"), defaultValue: NSDate(timeIntervalSince1970: 0))	
    t.column(Expression<NSDate>("updated_at"), defaultValue: NSDate(timeIntervalSince1970: 0))	
    t.column(...)  

})                             

// CREATE TABLE "Products" (
//		"id" INTEGER PRIMARY KEY NOT NULL,
//		created_at INTEGER DEFAULT (0),
//		created_at INTEGER DEFAULT (0),
//     ...
//	)
  
```
"created\_at"和"updated\_at"字段的单位是毫秒ms。

### 从 ActiveSQLite0.4.0 升级到 0.4.1

ActiveSQLite0.4.0 用3种类型定义属性: T, T!, T?.<br>
ActiveSQLite0.4.1 用两种类型定义属性: T, T?.

| 类型		|  0.4.0    | 0.4.1    |
| --------------- | --------------- | ----------- |
| `T `    | `不为空`     | `不为空`   |
| `T! `   | `不为空`     | `可为空。使用T?替换`|
| `T?`    | `可为空`     | `可为空`|
| `主键 id` | `是 T! 类型`	|`是 T? 类型`|

【数据库字段的默认值参考本文档第一张表】。

### 映射
你可以自定义表的名字, 列的名字，还可以设置瞬时属性不存在数据库中。

#### 1. 映射数据库名

如果你只用了一个数据库，那么设置完 setDefaultDB（path:name:) 就可以了，不需要做额外的操作。如果你用了多个数据库，设置表在特定的数据库，只需要写model的时候，重写dbName。

``` swift

ASConfigration.setDefaultDB(path:"db file path", name: "default db name")
ASConfigration.setDB(path: "other db file path", name: "other db name")

override class var dbName:String?{
    return "other db name"
}
```

#### 2. 映射表名

默认的表名和类名相同。设置其他表名的时候，只需要在model定义中重写nameOfTable。

``` swift
//设置表名为 "ProductTable"
override class var nameOfTable: String{
    return "ProductTable"
}
```

#### 3. 映射列名

默认的列名和属性名相同，不需要做额外的操作。如果要使属性名和列名不同，需要重写mapper()

``` swift
override func mapper() -> [String:String]{
    return ["property_name":"column_name"];
}
```

如果要设置主键对应的列名，需要重写 PRIMARY_KEY 和 mapper()。

``` swift
override class var PRIMARY_KEY:String{
    return "_id"
}
    
override func mapper() -> [String:String]{
    return ["id":"_id"]
}
``` 

#### 4. 瞬时属性。

瞬时属性不会被存在数据库中。

``` swift
override class func transientTypess() -> [String]{
    return ["isSelected"]
}

```
ActiveSQLite 仅仅保存三种属性类型 (String,NSNumber,NSDate)到数据库。 如果属性不是这三种类型，那么不会被存入数据库，它们被当做瞬时属性看待。

#### 5. 自动创建 "created\_at" and "updated\_at" columns.

只需要重写 isSaveDefaulttimestamp, 不需要做任何其他事情, 父类 ASModel 已经定义了 "created\_at" 和 "updated\_at" 属性。

```swift

override class var isSaveDefaulttimestamp:Bool{
    return true
}
    
```

### 表约束
如果你要自定义列, 你仅需要实现CreateColumnsProtocol协议的createColumns方法，那么ActiveSQLite就不会自动创建列。写自己的建列语句，要注意列名和属性名必须一致，否则不能自动从查询sql封装数据库模型对象。

```swift

class Users:ASModel,CreateColumnsProtocol{
    var name:String = ""
    var email:String = ""
    var age:Int?
   
    func createColumns(t: TableBuilder) {
        t.column(Expression<NSNumber>("id"), primaryKey: true)
        t.column(Expression<String>("name"),defaultValue:"Anonymous")
        t.column(Expression<String>("email"), , check: email.like("%@%"))
    }
}
```

更多信息查考SQLite.swift的文档[table constraints document](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#table-constraints)。

## 插入记录
有三个方法用来插入记录。

插入一条。

```swift
func insert()throws ;
```

插入多条。

```swift
class func insertBatch(models:[ASModel])throws ;

```

保存方法。

如果数据库模型对象的 id == nil，那么执行插入。如果id != nil那么执行更新语句。

```swift
func save() throws;
```

例如:

```swift
let u = Users()
u.name = "Kevin"
try! u.save()
                
var products = [Product]()
for i in 1 ..< 8 {
    let p = Product()
    p.name = "iPhone-\(i)"
    p.price = NSNumber(value:i)
    products.append(p)
}
                
try! Product.insertBatch(models: products)

```
更多信息可以看ActiveSQLite的源码和例子, 也可以查阅SQLite.swift的文档[Inserting Rows document](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#inserting-rows)。

## 更新记录
有三种更新策略。

### 1. 通过改属性值

首先修改属性的值，然后执行save() 或者 update() 或者 updateBatch()。
	
```swift
p.name = "zhoukai"
p.save()

```
	
### 2. 通过属性名字符串和属性值

```swift
//更新一条
u.update("name",value:"3ds")
u.update(["name":"3ds","price":NSNumber(value:199)])


//更新多条
Product.update(["name": "3ds","price":NSNumber(value:199)], where: ["id": NSNumber(1)])

```

### 2. 通过SQLite.swift的Setter


```swift
//更新一条记录
p.update([Product.price <- NSNumber(value:199))

//更新多条
Product.update([Product.price <- NSNumber(value:199), where: Product.name == "3ds")
```

了解更多请看ActiveSQLite的源码和例子, 查看SQLite.swift的文档[Updating Rows document](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#updating-rows) , [Setters document](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#setters)。


## 查询记录

使用findFirst方法查询一条记录，使用findAll方法查询多条记录。

方法名前缀是"find"的是类方法，这种方法一次性查询出结果。

#### 1.通过属性名字符串和属性值查询

```swift
let p = Product.findFirst("name",value:"iWatch")

let ps = Product.findAll("name",value:"iWatch",orders:["price",false])

```

#### 2.通过SQLite.swift的Expression查询

```swift
let id = Expression<NSNumber>("id")
let name = Expression<String>("name")

let arr = Product.findAll(name == "iWatch")

let ps = Product.findAll(id > NSNumber(value:100), orders: [Product.id.asc])

```

### 链式查询
链式查询方法是属性方法。

```swift
let products = Product().where(Expression<NSNumber>("code") > 3)
                                .order(Product.code)
                                .limit(5)
                                .run()

```
不要忘记执行run()。

更多复杂的查询参考ActiveSQLite的源码和例子。和SQLite.swift的文档[Building Complex Queries](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#building-complex-queries)。

## 表达式Expression

SQLite.swift再更新update和查询select操作中，使用表达式Expression转换成SQL的'where'判断，。更多复杂的表达式用法，参考文档[filtering-rows](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#filtering-rows)。

## 删除记录

```swift
//1. 删除一条
try? product.delete()

//2. 删除所有
try? Product.deleteAll()

//3. 通过表达式Expression链式删除。
try? Product().where(Expression<NSNumber>("code") > 3)
                                .runDelete()

```

## 事务

建议把所有的insert，update，delete操作和alter表的代码全部放在ActiveSQLite.save代码块中。一个块中的sql操作在同一个事务当中。

```swift
 ActiveSQLite.save({ 

                var products = [Product]()
                for i in 0 ..< 3 {
                    let p = Product()
                    p.name = "iPhone-\(i)"
                    p.price = NSNumber(value:i)
                    products.append(p)
                }
                try Product.insertBatch(models: products)
                

                let u = Users()
                u.name = "Kevin"
                try u.save()
                

            }, completion: { (error) in
                
                if error != nil {
                    debugPrint("transtion fails \(error)")
                }else{
                    debugPrint("transtion success")
                }

            })

```

## 异步

ActiveSQLite.saveAsync是一个异步的操作，当然代码块中的sql也在同一个事务当中。

```swift
 ActiveSQLite.saveAsync({ 
			.......

            }, completion: { (error) in
                ......
            })
```
## 改变表结构
### 重命名表和添加列

#### 第1步. 用新的表名做映射，添加新的属性。

```swift
class Product{
	var name:String!
	
	var newColumn:String!
	override class var nameOfTable: String{
    	return "newTableName"
	}
	
}
```

#### Step 2. 当数据库版本改变时候，执行修改表名和添加列sql，并放在同一个事务中。

```swift
let db = DBConnection.sharedConnection.db
            if db.userVersion == 0 {
                ActiveSQLite.saveAsync({
                    try Product.renameTable(oldName:"oldTableName",newName:"newTableName")
                    try Product.addColumn(["newColumn"])
                    
                }, completion: { (error) in
                    if error == nil {
                    
                    	db.userVersion = 1
                    }
                })
                
            }             

```
更多SQLite.swift的修改表信息参看 [Altering the Schema](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#altering-the-schema)。

### 索引

```swift
	let name = Expression<String>("name")
	Product.createIndex(name)
	Product.dropIndex(name)
```

更多信息查看 [Indexes of SQLite.swift Document](https://github.com/stephencelis/SQLite.swift/blob/master/Documentation/Index.md#indexes)。

### 删除表
```swift
Product.dropTable()
```

## 日志
有四种日志级别，分别是: debug,info,warn,error。
默认的日志级别是info。像这样来设置日志级别：

```swift
//1. 设置日志级别
ASConfigration.logLevel = .debug

//2. 设置数据库路径
ASConfigration.dbPath = "..."
```
保证首先设置日志级别，后设置数据库路径。


## 硬件需求
- iOS 8.0+  
- Xcode 10.2
- Swift 5

## 安装

### Cocoapods

再Podfile文件中添加:

```ruby
pod "ActiveSQLite"
```

## 作者

Kevin Zhou

- 邮件: <wumingapie@gmail.com>
- **Facebook**: [**wumingapie**](https://www.facebook.com/wumingapie)
- **微信&QQ**: 458545592

## License

ActiveSQLite is available under the MIT license. See the LICENSE file for more info.
