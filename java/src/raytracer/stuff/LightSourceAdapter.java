package raytracer.stuff;

import java.lang.reflect.Type;

import com.google.gson.JsonDeserializationContext;
import com.google.gson.JsonDeserializer;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParseException;
import com.google.gson.JsonPrimitive;
import com.google.gson.JsonSerializationContext;
import com.google.gson.JsonSerializer;

import raytracer.light.LightSource;

public class LightSourceAdapter implements JsonDeserializer<LightSource> ,JsonSerializer<LightSource>{
    
    @Override
    public JsonElement serialize(LightSource src, Type typeOfSrc, JsonSerializationContext context) {
        var result = new JsonObject();
        result.add("type", new JsonPrimitive(src.getClass().getSimpleName()));
        result.add("properties", context.serialize(src, src.getClass()));
 
        return result;
    }
    
    @Override
    public LightSource deserialize(JsonElement json, Type typeOfT, JsonDeserializationContext context) throws JsonParseException {
        var jsonObject = json.getAsJsonObject();
        String type = jsonObject.get("type").getAsString();
        var element = jsonObject.get("properties");
        try {
            return context.deserialize(element, Class.forName("raytracer.light." + type));
        } catch (ClassNotFoundException cnfe) {
            throw new JsonParseException("Unknown element type: " + type, cnfe);
        }
    }
}
