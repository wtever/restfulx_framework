package org.ruboss.serializers {
  import flash.utils.getDefinitionByName;
  
  import mx.utils.ObjectUtil;
  
  import org.ruboss.Ruboss;
  import org.ruboss.collections.ModelsCollection;
  import org.ruboss.models.RubossModel;
  import org.ruboss.utils.ModelsMetadata;
  import org.ruboss.utils.RubossUtils;
  
  public class GenericSerializer implements ISerializer {
    
    protected var state:ModelsMetadata;
    
    public function GenericSerializer() {
      state = Ruboss.models.state;
    }

    public function marshall(object:Object, recursive:Boolean = false, metadata:Object = null):Object {
      return object;
    }
    
    public function unmarshall(object:Object):Object {
      return object;
    }

    protected function processHasManyThroughRelationships(object:Object, fqn:String):void {
      for each (var relationship:Object in state.hmts[state.controllers[fqn]]) {
        try {
          // relationship["type"] = fqn (e.g. package::Client)
          // relationship["attribute"] = plural name of the reference (e.g. timesheets)
          var relType:String = relationship["type"];
          
          // if the relationship attribute is called something other than the plural of the class name
          // refType will specify what it is
          var refKey:String = (!RubossUtils.isEmpty(relationship["refType"])) ? relationship["refType"] : relationship["attribute"];

          var localSingleName:String = state.names[relType]["single"];
          var localPluralName:String = state.names[relType]["plural"];

          var refType:String = state.fqns[refKey];
          var refNameSingle:String = state.names[refType]["single"];
          var refNamePlural:String = state.names[refType]["plural"];
  
          // e.g. object[client][timesheets]
          var items:ModelsCollection = object[localSingleName][relationship["attribute"]];
          if (items == null) {
            items = new ModelsCollection;
          }
          
          // form 1, e.g. object[timesheet]
          if (object.hasOwnProperty(localSingleName) && object.hasOwnProperty(refNameSingle)) {
            if (items.hasItem(object[refNameSingle])) {
              items.setItem(object[refNameSingle]);
            } else {
              items.addItem(object[refNameSingle]);
            }
            object[localSingleName][relationship["attribute"]] = items;
            
          // form 2 e.g. object[authors]
          } else if (object.hasOwnProperty(localSingleName) && object.hasOwnProperty(refNamePlural)) {
            if (object[refNamePlural] == null) {
              object[refNamePlural] = new ModelsCollection;
            }
            object[localSingleName][relationship["attribute"]] = object[refNamePlural];          
          }
        } catch (e:Error) {
          // do something
        }
      }
    }
    
    protected function processNestedArray(array:Object, type:String):ModelsCollection {
      return new ModelsCollection;
    }
    
    protected function unmarshallNode(source:Object, type:String = null):Object {
      return source;
    }

    protected function unmarshallElement(node:Object, object:Object, element:Object, targetName:String, 
      defaultValue:*, fqn:String, updatingExistingReference:Boolean):void {
      var targetType:String = null;
      var isRef:Boolean = false;
      var isParentRef:Boolean = false;
      var isNestedArray:Boolean = false;
      var isNestedObject:Boolean = false;
      
      // if we got a node with a name that terminates in "_id" we check to see if
      // it's a model reference       
      if (targetName.search(/.*_id$/) != -1) {
        // name to check on the ruboss model object
        var checkName:String = targetName.replace(/_id$/, "");
        targetName = RubossUtils.toCamelCase(checkName);
        if (checkName == "parent") {
          targetType = fqn;
          isRef = true;
          isParentRef = true;
        } else {
          // check to see if it's a polymorphic association
          var polymorphicRef:String = node[checkName + "_type"];
          if (!RubossUtils.isEmpty(polymorphicRef)) {
            var polymorphicRefName:String = RubossUtils.lowerCaseFirst(polymorphicRef);
            if (state.fqns[polymorphicRefName]) {
              targetType = state.fqns[polymorphicRefName];
              isRef = true;
            } else {
              throw new Error("Polymorphic type: " + polymorphicRef + " is not a valid Ruboss Model type.");
            }
          } else if (state.refs[fqn][targetName]) {
            targetType = state.refs[fqn][targetName]["type"];
            isRef = true;
          }
        }
      } else {
        targetName = RubossUtils.toCamelCase(targetName);
        try {
          targetType = state.refs[fqn][targetName]["type"];
          if (element.@type == "array") {
            isNestedArray = true;
          } else {
            isNestedObject = true;
            if (RubossUtils.isEmpty(targetType)) {
              // we potentially have a nested polymorphic relationship here
              var nestedPolymorphicRef:String = node[RubossUtils.toSnakeCase(targetName) + "_type"];
              if (!RubossUtils.isEmpty(nestedPolymorphicRef)) {
                targetType = state.fqns[nestedPolymorphicRef];
              }
            }
          }
        } catch (e:Error) {
          // normal property, a-la String
        }
      }
      
      if (object.hasOwnProperty(targetName)) {
        // if this property is a reference, try to resolve the 
        // reference and set up biderctional links between models
        if (isRef) {
          var refId:String = element.toString();
          if (RubossUtils.isEmpty(refId)) {
            if (isParentRef) {
              return;
            } else {
              throw new Error("error retrieving id from model: " + fqn + ", property: " + targetName);
            }
          }
          
          var ref:Object = ModelsCollection(Ruboss.models.cache.data[targetType]).withId(refId);
          if (ref == null) {
            ref = initializeModel(refId, targetType);
          }
  
          if (updatingExistingReference && object[targetName] != ref) {
            cleanupModelReferences(object, fqn);
          }
          
          var pluralName:String = state.refs[fqn][targetName]["referAs"];
          var singleName:String = pluralName;
          if (RubossUtils.isEmpty(pluralName)) {
            pluralName = (isParentRef) ? "children" : state.names[fqn]["plural"];
            singleName = state.names[fqn]["single"];
          }
              
          // if we've got a plural definition which is annotated with [HasMany] 
          // it's got to be a 1->N relationship           
          if (ref != null && ref.hasOwnProperty(pluralName) && 
            ObjectUtil.hasMetadata(ref, pluralName, "HasMany")) {
            var items:ModelsCollection = ModelsCollection(ref[pluralName]);
            if (items == null) {
              items = new ModelsCollection;
            }
            
            // add (or replace) the current item to the reference collection
            if (items.hasItem(object)) {
              items.setItem(object);
            } else {
              items.addItem(object);
            }
            
            ref[pluralName] = items;
  
          // if we've got a singular definition annotated with [HasOne] then it must be a 1->1 relationship
          // link them up
          } else if (ref != null && ref.hasOwnProperty(singleName) && 
            ObjectUtil.hasMetadata(ref, singleName, "HasOne")) {
            ref[singleName] = object;
          }
          // and the reverse
          object[targetName] = ref;
        } else if (isNestedArray) {
          object[targetName] = processNestedArray(element, targetType);
        } else if (isNestedObject) {
          if (ObjectUtil.hasMetadata(object, targetName, "HasOne") ||
            ObjectUtil.hasMetadata(object, targetName, "BelongsTo")) {
            var nestedRef:Object = unmarshallNode(element, targetType);
            object[targetName] = nestedRef;
          }
        } else {
          object[targetName] = defaultValue;
        }
      }      
    }

    protected function initializeModel(id:String, fqn:String):Object {
      var model:Object = new (getDefinitionByName(fqn) as Class);
      ModelsCollection(Ruboss.models.cache.data[fqn]).addItem(model);
      model["id"] = id;
      return model;
    }
    
    protected function addItemToCache(item:Object, type:String):void {
      var cached:ModelsCollection = ModelsCollection(Ruboss.models.cache.data[type]);
      if (cached.hasItem(item)) {
        cached.setItem(item);
      } else {
        cached.addItem(item);
      }      
    }

    // needs some testing too
    public function cleanupModelReferences(model:Object, fqn:String):void {
      var property:String = RubossUtils.toCamelCase(state.controllers[fqn]);
      var localName:String = state.names[fqn]["single"];
      for each (var dependency:String in state.eager[fqn]) {
        for each (var item:Object in Ruboss.models.cache.data[dependency]) {
          if (ObjectUtil.hasMetadata(item, property, "HasMany") && item[property] != null) {
            var items:ModelsCollection = ModelsCollection(item[property]);
            if (items.hasItem(model)) {
              items.removeItem(model);
            } 
          }
          if (ObjectUtil.hasMetadata(item, localName, "HasOne") && item[localName] != null) {
            item[localName] = null;
          }
        }
      }
      if (model.hasOwnProperty("parent") && model["parent"] != null && model["parent"].hasOwnProperty("children") &&
        model["parent"]["children"] != null) {
        var parentChildren:ModelsCollection = ModelsCollection(model["parent"]["children"]);
        if (parentChildren.hasItem(model)) {
          parentChildren.removeItem(model);
        }
      }
      if (model.hasOwnProperty("children") && model["children"] != null) {
        var children:ModelsCollection = ModelsCollection(model["children"]);
        for each (var child:Object in children) {
          Ruboss.models.cache.destroy(RubossModel(child));
        }  
      }
    }
  }
}