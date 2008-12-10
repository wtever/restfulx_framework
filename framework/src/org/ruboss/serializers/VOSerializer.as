package org.ruboss.serializers {
  import flash.utils.describeType;
  import flash.utils.getDefinitionByName;
  import flash.utils.getQualifiedClassName;
  
  import org.ruboss.Ruboss;
  import org.ruboss.collections.ModelsCollection;
  import org.ruboss.models.RubossModel;
  import org.ruboss.utils.RubossUtils;
  import org.ruboss.utils.TypedArray;
  
  public class VOSerializer extends GenericSerializer {

    private static var types:Object = {
      "int" : "integer",
      "uint" : "integer",
      "Boolean" : "boolean",
      "String" : "text",
      "Number" : "double",
      "Date" : "date",
      "DateTime" : "datetime"
    }

    public override function marshall(object:Object, recursive:Boolean = false, metadata:Object = null):Object {
      return marshallToVO(object, metadata);  
    }

    public override function unmarshall(object:Object):Object {
      if (object is TypedArray || object is RubossModel) {
        return object;
      }
      try {
        if (object is Array) {
          return unmarshallArray(object as Array);
        } else {
          var fqn:String = state.fqns[object["clazz"]];
          var clazz:Class = getDefinitionByName(fqn) as Class;
          return unmarshallNode(object, fqn);
        }
      } catch (e:Error) {
        throw new Error("could not unmarshall provided object");
      }
      return null;
    }
    
    private function unmarshallArray(instances:Array):Array {
      if (!instances || !instances.length) return instances;
      
      var results:TypedArray = new TypedArray;
      var fqn:String = state.fqns[instances[0]["clazz"]];
      var clazz:Class = getDefinitionByName(fqn) as Class;
        
      results.itemType = fqn;
      for each (var instance:Object in instances) {
        results.push(unmarshallNode(instance, fqn));
      }
      return results;
    }
    
    protected override function unmarshallNode(source:Object, type:String = null):Object {
      var fqn:String = type;
      var nodeId:String = source["id"];
      var updatingExistingReference:Boolean = false;
      if (!fqn || !nodeId) {
        throw new Error("cannot unmarshall " + source + " no mapping exists or received a node with invalid id");
      }
      
      var object:Object = ModelsCollection(Ruboss.models.cache.data[fqn]).withId(nodeId);
      
      if (object == null) {
        object = initializeModel(nodeId, fqn);
      } else {
        updatingExistingReference = true; 
      }
      
      var metadata:XML = describeType(getDefinitionByName(fqn));
      for (var property:String in source) {
        var targetName:String = property;
        var value:String = source[property];
        var targetType:String = getType(XMLList(metadata..accessor.(@name == targetName))[0]).toLowerCase();
        unmarshallElement(source, object, source[property], targetName, RubossUtils.cast(targetName, targetType, value),
        fqn, updatingExistingReference);
      }  
      
      addItemToCache(object, fqn);
      processHasManyThroughRelationships(object, fqn);

      return object;         
    }

    private function marshallToVO(object:Object, metadata:Object = null):Object {        
      var fqn:String = getQualifiedClassName(object);
      
      var result:Object = new Object;
      for each (var node:XML in describeType(object)..accessor) {
        if (RubossUtils.isIgnored(node) || RubossUtils.isHasOne(node) || RubossUtils.isHasMany(node)) continue;
          
        var nodeName:String = node.@name;
        var type:String = node.@type;
        var snakeName:String = RubossUtils.toSnakeCase(nodeName);
        
        if (RubossUtils.isInvalidPropertyType(type) || RubossUtils.isInvalidPropertyName(nodeName)) continue;
        
        // treat model objects specially (we are only interested in serializing
        // the [BelongsTo] end of the relationship
        if (RubossUtils.isBelongsTo(node)) {
          var descriptor:XML = RubossUtils.getAttributeAnnotation(node, "BelongsTo")[0];
          var polymorphic:Boolean = (descriptor.arg.(@key == "polymorphic").@value.toString() == "true") ? true : false;

          if (object[nodeName]) {
            result[snakeName + "_id"] = object[nodeName]["id"]; 
            if (polymorphic) {
              result[snakeName + "_type"] = getQualifiedClassName(object[nodeName]).split("::")[1];
            }
          } else {
            result[snakeName + "_id"] = null;
          }
        } else {
          if (object[nodeName]) {
            result[snakeName] = 
              RubossUtils.uncast(object, nodeName);
          }
        }
      }

      result["clazz"] = fqn.split("::")[1];
      
      if (metadata != null) {
        result["_metadata"] = metadata;
      }
            
      return result;
    }

    private function getType(node:XML):String {
      var type:String = node.@type;
      var result:String = types[type];
      if (state.fqns[type]) {
        return types["String"];
      } else if (RubossUtils.isDateTime(node)) {
        return types["DateTime"];
      } else {
        return (result == null) ? types["String"] : result; 
      }
    }
  }
}