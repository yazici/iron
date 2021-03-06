package iron.data;

import kha.graphics4.PipelineState;
import kha.graphics4.ConstantLocation;
import kha.graphics4.TextureUnit;
import kha.graphics4.VertexStructure;
import kha.graphics4.VertexData;
import kha.graphics4.StencilAction;
import kha.graphics4.CompareMode;
import kha.graphics4.CullMode;
import kha.graphics4.BlendingOperation;
import kha.graphics4.BlendingFactor;
import kha.graphics4.TextureAddressing;
import kha.graphics4.TextureFilter;
import kha.graphics4.MipMapFilter;
import iron.data.SceneFormat;

class ShaderData {

	public var name:String;
	public var raw:TShaderData;

	public var contexts:Array<ShaderContext> = [];

	public function new(raw:TShaderData, done:ShaderData->Void, overrideContext:TShaderOverride = null) {
		this.raw = raw;
		this.name = raw.name;

		for (c in raw.contexts) contexts.push(null);
		var contextsLoaded = 0;

		for (i in 0...raw.contexts.length) {
			var c = raw.contexts[i];

			new ShaderContext(c, function(con:ShaderContext) {
				contexts[i] = con;
				contextsLoaded++;
				if (contextsLoaded == raw.contexts.length) done(this);
			}, overrideContext);
		}
	}

	public static function parse(file:String, name:String, done:ShaderData->Void, overrideContext:TShaderOverride = null) {
		Data.getSceneRaw(file, function(format:TSceneFormat) {
			var raw:TShaderData = Data.getShaderRawByName(format.shader_datas, name);
			if (raw == null) {
				trace('Shader data "$name" not found!');
				done(null);
			}
			new ShaderData(raw, done, overrideContext);
		});
	}

	public function delete() {
		for (c in contexts) c.delete();
	}

	public function getContext(name:String):ShaderContext {
		for (c in contexts) if (c.raw.name == name) return c;
		return null;
	}
}

class ShaderContext {
	public var raw:TShaderContext;

	public var pipeState:PipelineState;
	public var constants:Array<ConstantLocation>;
	public var textureUnits:Array<TextureUnit>;
	// public var paramsSet:Array<Bool>;

	var structure:VertexStructure;
	var instancingType = 0;
	var overrideContext:TShaderOverride;

	public function new(raw:TShaderContext, done:ShaderContext->Void, overrideContext:TShaderOverride = null) {
		this.raw = raw;
		this.overrideContext = overrideContext;
		parseVertexStructure();
		compile(done);
	}

	public function compile(done:ShaderContext->Void) {
		if (pipeState != null) pipeState.delete();
		pipeState = new PipelineState();
		constants = [];
		textureUnits = [];
		// paramsSet = [];

		// Instancing
		if (instancingType > 0) {
			var instStruct = new VertexStructure();
			instStruct.add("ipos", VertexData.Float3);
			if (instancingType == 2 || instancingType == 4) {
				instStruct.add("irot", VertexData.Float3);
			}
			if (instancingType == 3 || instancingType == 4) {
				instStruct.add("iscl", VertexData.Float3);
			}
			instStruct.instanced = true;
			pipeState.inputLayout = [structure, instStruct];
		}
		// Regular
		else {
			pipeState.inputLayout = [structure];
		}
		
		// Depth
		pipeState.depthWrite = raw.depth_write;
		pipeState.depthMode = getCompareMode(raw.compare_mode);
		
		// Stencil
		if (raw.stencil_mode != null) {
			if (raw.stencil_mode == "always")
				pipeState.stencilMode = CompareMode.Always;
			else if (raw.stencil_mode == "equal")
				pipeState.stencilMode = CompareMode.Equal;
			else if (raw.stencil_mode == "not_equal")
				pipeState.stencilMode = CompareMode.NotEqual;
		}
		if (raw.stencil_pass != null) {
			if (raw.stencil_pass == "replace")
				pipeState.stencilBothPass = StencilAction.Replace;
			else if (raw.stencil_pass == "keep")
				pipeState.stencilBothPass = StencilAction.Keep;
		}
		if (raw.stencil_fail != null && raw.stencil_fail == "keep") {
			pipeState.stencilDepthFail = StencilAction.Keep;
			pipeState.stencilFail = StencilAction.Keep;
		}
		if (raw.stencil_reference_value != null) {
			pipeState.stencilReferenceValue = Static(raw.stencil_reference_value);
		}	
		// pipeState.stencilReadMask = raw.stencil_read_mask;
		// pipeState.stencilWriteMask = raw.stencil_write_mask;

		// Cull
		pipeState.cullMode = getCullMode(raw.cull_mode);
		
		// Blending
		if (raw.blend_source != null) pipeState.blendSource = getBlendingFactor(raw.blend_source);
		if (raw.blend_destination != null) pipeState.blendDestination = getBlendingFactor(raw.blend_destination);
		if (raw.blend_operation != null) pipeState.blendOperation = getBlendingOperation(raw.blend_operation);
		if (raw.alpha_blend_source != null) pipeState.alphaBlendSource = getBlendingFactor(raw.alpha_blend_source);
		if (raw.alpha_blend_destination != null) pipeState.alphaBlendDestination = getBlendingFactor(raw.alpha_blend_destination);
		if (raw.alpha_blend_operation != null) pipeState.alphaBlendOperation = getBlendingOperation(raw.alpha_blend_operation);

		// Color write mask
		if (raw.color_write_red != null) pipeState.colorWriteMaskRed = raw.color_write_red;
		if (raw.color_write_green != null) pipeState.colorWriteMaskGreen = raw.color_write_green;
		if (raw.color_write_blue != null) pipeState.colorWriteMaskBlue = raw.color_write_blue;
		if (raw.color_write_alpha != null) pipeState.colorWriteMaskAlpha = raw.color_write_alpha;

		// Per target masks
		if (raw.color_writes_red != null) for (i in 0...raw.color_writes_red.length) pipeState.colorWriteMasksRed[i] = raw.color_writes_red[i];
		if (raw.color_writes_green != null) for (i in 0...raw.color_writes_green.length) pipeState.colorWriteMasksGreen[i] = raw.color_writes_green[i];
		if (raw.color_writes_blue != null) for (i in 0...raw.color_writes_blue.length) pipeState.colorWriteMasksBlue[i] = raw.color_writes_blue[i];
		if (raw.color_writes_alpha != null) for (i in 0...raw.color_writes_alpha.length) pipeState.colorWriteMasksAlpha[i] = raw.color_writes_alpha[i];

		// Conservative raster for voxelization
		if (raw.conservative_raster != null) pipeState.conservativeRasterization = raw.conservative_raster;

		// Shaders
		if (raw.shader_from_source) {
			pipeState.vertexShader = kha.graphics4.VertexShader.fromSource(raw.vertex_shader);
			pipeState.fragmentShader = kha.graphics4.FragmentShader.fromSource(raw.fragment_shader);
			// if (raw.geometry_shader != null) {
				// pipeState.geometryShader = kha.graphics4.GeometryShader.fromSource(raw.geometry_shader);
			// }
			// if (raw.tesscontrol_shader != null) {
				// pipeState.tessellationControlShader = kha.graphics4.TessellationControlShader.fromSource(raw.tesscontrol_shader);
			// }
			// if (raw.tesseval_shader != null) {
				// pipeState.tessellationEvaluationShader = kha.graphics4.TessellationEvaluationShader.fromSource(raw.tesseval_shader);
			// }
			finishCompile(done);
		}
		else {

			#if (arm_noembed && !kha_debug_html5) // Load shaders manually

			var shadersLoaded = 0;
			var numShaders = 2;
			if (raw.geometry_shader != null) numShaders++;
			if (raw.tesscontrol_shader != null) numShaders++;
			if (raw.tesseval_shader != null) numShaders++;

			function loadShader(file:String, type:Int) {

				#if (kha_webgl && !kha_node)
				var ar = file.split('.');
				file = ar[0] + '-webgl2.' + ar[1];
				var path = '../html5-resources/' + file + '.essl';
				#elseif kha_opengl
				var path = '../krom-resources/' + file + '.glsl';
				#else
				var path = '../krom-resources/' + file + '.d3d11';
				#end
				Data.getBlob(path, function(b:kha.Blob) {
					if (type == 0) pipeState.vertexShader = new kha.graphics4.VertexShader([b], [file]);
					else if (type == 1) pipeState.fragmentShader = new kha.graphics4.FragmentShader([b], [file]);
					#if !kha_webgl
					else if (type == 2) pipeState.geometryShader = new kha.graphics4.GeometryShader([b], [file]);
					else if (type == 3) pipeState.tessellationControlShader = new kha.graphics4.TessellationControlShader([b], [file]);
					else if (type == 4) pipeState.tessellationEvaluationShader = new kha.graphics4.TessellationEvaluationShader([b], [file]);
					#end
					shadersLoaded++;
					if (shadersLoaded >= numShaders) finishCompile(done);
				});
			}
			loadShader(raw.vertex_shader, 0);
			loadShader(raw.fragment_shader, 1);
			if (raw.geometry_shader != null) loadShader(raw.geometry_shader, 2);
			if (raw.tesscontrol_shader != null) loadShader(raw.tesscontrol_shader, 3);
			if (raw.tesseval_shader != null) loadShader(raw.tesseval_shader, 4);

			#else

			pipeState.fragmentShader = Reflect.field(kha.Shaders, StringTools.replace(raw.fragment_shader, ".", "_"));
			pipeState.vertexShader = Reflect.field(kha.Shaders, StringTools.replace(raw.vertex_shader, ".", "_"));

			if (raw.geometry_shader != null) {
				pipeState.geometryShader = Reflect.field(kha.Shaders, StringTools.replace(raw.geometry_shader, ".", "_"));
			}
			if (raw.tesscontrol_shader != null) {
				pipeState.tessellationControlShader = Reflect.field(kha.Shaders, StringTools.replace(raw.tesscontrol_shader, ".", "_"));
			}
			if (raw.tesseval_shader != null) {
				pipeState.tessellationEvaluationShader = Reflect.field(kha.Shaders, StringTools.replace(raw.tesseval_shader, ".", "_"));
			}
			finishCompile(done);

			#end
		}
	}

	function finishCompile(done:ShaderContext->Void) {
		// Override specified values
		if (overrideContext != null) {
			if (overrideContext.cull_mode != null) {
				pipeState.cullMode = getCullMode(overrideContext.cull_mode);
			}
		}

		pipeState.compile();

		if (raw.constants != null) {
			for (c in raw.constants) addConstant(c);
		}

		if (raw.texture_units != null) {
			for (tu in raw.texture_units) addTexture(tu);
		}

		done(this);
	}

	public static function parseData(data:String):VertexData {
		if (data == "float1") return VertexData.Float1;
		else if (data == "float2") return VertexData.Float2;
		else if (data == "float3") return VertexData.Float3;
		else if (data == "float4") return VertexData.Float4;
		else if (data == "short2norm") return VertexData.Short2Norm;
		else if (data == "short4norm") return VertexData.Short4Norm;
		return VertexData.Float1;
	}
	
	function parseVertexStructure() {
		structure = new VertexStructure();
		var ipos = false;
		var irot = false;
		var iscl = false;
		for (elem in raw.vertex_elements) {
			#if cpp
			if (Reflect.field(elem, 'name') == 'ipos') { ipos = true; continue; }
			if (Reflect.field(elem, 'name') == 'irot') { irot = true; continue; }
			if (Reflect.field(elem, 'name') == 'iscl') { iscl = true; continue; }
			#else
			if (elem.name == 'ipos') { ipos = true; continue; }
			if (elem.name == 'irot') { irot = true; continue; }
			if (elem.name == 'iscl') { iscl = true; continue; }
			#end
			structure.add(elem.name, parseData(elem.data));
		}
		if (ipos && !irot && !iscl) instancingType = 1;
		else if (ipos && irot && !iscl) instancingType = 2;
		else if (ipos && !irot && iscl) instancingType = 3;
		else if (ipos && irot && iscl) instancingType = 4;
	}

	public function delete() {
		if (pipeState.fragmentShader != null) pipeState.fragmentShader.delete();
		if (pipeState.vertexShader != null) pipeState.vertexShader.delete();
		if (pipeState.geometryShader != null) pipeState.geometryShader.delete();
		if (pipeState.tessellationControlShader != null) pipeState.tessellationControlShader.delete();
		if (pipeState.tessellationEvaluationShader != null) pipeState.tessellationEvaluationShader.delete();
		pipeState.delete();
	}

	function getCompareMode(s:String):CompareMode {
		switch(s) {
		case "always": return CompareMode.Always;
		case "never": return CompareMode.Never;
		case "less": return CompareMode.Less;
		case "less_equal": return CompareMode.LessEqual;
		case "greater": return CompareMode.Greater;
		case "greater_equal": return CompareMode.GreaterEqual;
		case "equal": return CompareMode.Equal;
		case "not_equal": return CompareMode.NotEqual;
		default: return CompareMode.Less;
		}
	}

	function getCullMode(s:String):CullMode {
		switch(s) {
		case "none": return CullMode.None;
		case "clockwise": return CullMode.Clockwise;
		default: return CullMode.CounterClockwise;
		}			
	}

	function getBlendingOperation(s:String):BlendingOperation {
		switch(s) {
		case "add": return BlendingOperation.Add;
		case "subtract": return BlendingOperation.Subtract;
		case "reverse_subtract": return BlendingOperation.ReverseSubtract;
		case "min": return BlendingOperation.Min;
		case "max": return BlendingOperation.Max;
		default: return BlendingOperation.Add;
		}
	}
	
	function getBlendingFactor(s:String):BlendingFactor {
		switch(s) {
		case "blend_one": return BlendingFactor.BlendOne;
		case "blend_zero": return BlendingFactor.BlendZero;
		case "source_alpha": return BlendingFactor.SourceAlpha;
		case "destination_alpha": return BlendingFactor.DestinationAlpha;
		case "inverse_source_alpha": return BlendingFactor.InverseSourceAlpha;
		case "inverse_destination_alpha": return BlendingFactor.InverseDestinationAlpha;
		case "source_color": return BlendingFactor.SourceColor;
		case "destination_color": return BlendingFactor.DestinationColor;
		case "inverse_source_color": return BlendingFactor.InverseSourceColor;
		case "inverse_destination_color": return BlendingFactor.InverseDestinationColor;
		default: return BlendingFactor.Undefined;
		}
	}

	function getTextureAddresing(s:String):TextureAddressing {
		switch(s) {
		case "repeat": return TextureAddressing.Repeat;
		case "mirror": return TextureAddressing.Mirror;
		default: return TextureAddressing.Clamp;
		}
	}

	function getTextureFilter(s:String):TextureFilter {
		switch(s) {
		case "point": return TextureFilter.PointFilter;
		case "linear": return TextureFilter.LinearFilter;
		default: return TextureFilter.AnisotropicFilter;
		}	
	}

	function getMipmapFilter(s:String):MipMapFilter {
		switch(s) {
		case "no": return MipMapFilter.NoMipFilter;
		case "point": return MipMapFilter.PointMipFilter;
		default: return MipMapFilter.LinearMipFilter;
		}
	}

	function addConstant(c:TShaderConstant) {
		constants.push(pipeState.getConstantLocation(c.name));
	}

	function addTexture(tu:TTextureUnit) {
		var unit = pipeState.getTextureUnit(tu.name);
		textureUnits.push(unit);
		// paramsSet.push(false);
	}
	
	public function setTextureParameters(g:kha.graphics4.Graphics, unitIndex:Int, tex:TBindTexture) {
		// This function is called for samplers set using material context		
		var unit = textureUnits[unitIndex];
		g.setTextureParameters(unit,
			tex.u_addressing == null ? TextureAddressing.Repeat : getTextureAddresing(tex.u_addressing),
			tex.v_addressing == null ? TextureAddressing.Repeat : getTextureAddresing(tex.v_addressing),
			tex.min_filter == null ? TextureFilter.LinearFilter : getTextureFilter(tex.min_filter),
			tex.mag_filter == null ? TextureFilter.LinearFilter : getTextureFilter(tex.mag_filter),
			tex.mipmap_filter == null ? MipMapFilter.NoMipFilter : getMipmapFilter(tex.mipmap_filter));
	}
}
