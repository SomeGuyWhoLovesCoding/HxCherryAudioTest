package;

import cpp.Native;
import cpp.Star;
import cpp.Pointer;

import cpp.UInt32;
import cpp.UInt64;

import haxeal.HaxeAL;
import haxeal.HaxeALC;
import haxeal.ALObjects.ALContext;
import haxeal.ALObjects.ALDevice;

import cherry.Audio;

@:publicFields
class SoundManager {
	private static var sources:Map<String, Source> = [];
	private static var disposed(default, null):Bool;

	private static var context(default, null):ALContext;
	private static var device(default, null):ALDevice;

	static function init() {
		disposed = false;

		final defaultDeviceName:String = HaxeALC.getString(null, HaxeALC.DEFAULT_DEVICE_SPECIFIER);
		device = HaxeALC.openDevice(defaultDeviceName);

		context = HaxeALC.createContext(device, [HaxeALC.SYNC, HaxeALC.REFRESH]);

		if (!HaxeALC.makeContextCurrent(context)) {
			Sys.println("Failed to make OpenAL context current");
			Sys.exit(1);
		}

		final zero64:UInt64 = 0;

		sys.thread.Thread.create(() -> {
			while (true) {
				Sys.sleep(0.001);

				if (disposed) break;

				for (key in sources.keys()) {
					var source = sources[key];

					Sys.println(source.time);
					if (source.time > source.length - 20) source.stop();

					if (HaxeAL.getSourcei(source.source, HaxeAL.SOURCE_STATE) != HaxeAL.PLAYING) continue;

					while (HaxeAL.getSourcei(source.source, HaxeAL.BUFFERS_PROCESSED) > 0) {
						final buffers:Array<UInt32> = HaxeAL.sourceUnqueueBuffers(source.source, 1);

						source.fillBuffer(buffers[0]);
						HaxeAL.sourceQueueBuffers(source.source, buffers);
						source.bufsGoing++;
					}
				}
			}
		});
	}

	static function uninit() {
		for (source in sources) {
			source.dispose();
		}
		sources.clear();

		HaxeALC.destroyContext(context);
		HaxeALC.closeDevice(device);

		disposed = true;
	}

	static function load(filePath:String, key:String) {
		sources[key] = new Source([filePath]);
	}

	static function loadMultiple(filePaths:Array<String>, key:String) {
		sources[key] = new Source(filePaths);
	}

	inline static function get(key:String) {
		return sources[key];
	}

	private static function dispose(key:String) {
		sources[key].dispose();
		sources.remove(key);
	}
}

@:publicFields
private class Source {
	var bufsGoing:Float;
	var timeAdded(default, null):Float;

	var source:UInt32;
	var buffers:Array<UInt32>;
	var streams:Array<AudioStreamWrapper> = [];

	var disposed(default, null):Bool;

	var playing(get, never):Bool;

	inline function get_playing() {
		return HaxeAL.getSourcei(source, HaxeAL.SOURCE_STATE) == HaxeAL.PLAYING;
	}

	var stopped(get, never):Bool;

	inline function get_stopped() {
		return HaxeAL.getSourcei(source, HaxeAL.SOURCE_STATE) == HaxeAL.STOPPED;
	}

	var length(default, null):Float;

	var time(get, set):Float;

	inline function get_time() {
		return (HaxeAL.getSourcef(source, HaxeAL.SEC_OFFSET) * 1000) + (1000 * bufsGoing) + timeAdded;
	}

	inline function set_time(value:Float) {
		if (value < 0) {
			value = 0;
		}

		bufsGoing = 0;
		timeAdded = value;

		if (value > length) {
			HaxeAL.sourceStop(source);
			return value;
		}

		if (!disposed) {
			var paused = stopped || HaxeAL.getSourcei(source, HaxeAL.SOURCE_STATE) == HaxeAL.PAUSED;

			for (stream in streams) Audio.streamSeekToSample(stream.stream, untyped ((time * 0.001) * stream.stream.meta.sampleRate));

			// Stop the source
			HaxeAL.sourceStop(source);

			// Unqueue the processed buffer
			var queuedBuffers:Array<UInt32> = HaxeAL.sourceUnqueueBuffers(source, 3);

			// Refill each buffer with new audio data
			for (i in 0...queuedBuffers.length) fillBuffer(queuedBuffers[i]);

			// Requeue the buffer
			HaxeAL.sourceQueueBuffers(source, queuedBuffers);

			// Play the source
			HaxeAL.sourcePlay(source);

			if (paused) {
				HaxeAL.sourcePause(source);
			}
		}

		return value;
	}

	function new(filePaths:Array<String>) {
		source = HaxeAL.createSource();

		buffers = HaxeAL.createBuffers(4);

		var curLen:Float = 0;
		for (filePath in filePaths) {
			var stream = new AudioStreamWrapper(Audio.streamFile(filePath, DETECT));
			streams.push(stream);
			var audioLen = Audio.streamGetLength(stream.stream) * 1000;
			if (curLen < audioLen) {
				curLen = audioLen;
			}
		}

		length = curLen;

		for (i in 0...4) fillBuffer(buffers[i]);

		HaxeAL.sourceQueueBuffers(source, buffers);
	}

	function play() {
		HaxeAL.sourcePlay(source);
	}

	function pause() {
		HaxeAL.sourcePause(source);
	}

	function stop() {
		HaxeAL.sourceStop(source);
	}

	function dispose() {
		for (stream in streams) Audio.streamClose(stream.stream);

		HaxeAL.deleteSource(source);
		HaxeAL.deleteBuffers(buffers);

		disposed = true;
	}

	function fillBuffer(buffer:UInt32) {
		var streamOne:AudioStreamWrapper = streams[0];
		final pcm:PCMData = Audio.decodeSamples(streamOne.stream, FLOAT_32, streamOne.stream.meta.sampleRate);
		var channels = streamOne.stream.meta.channels;
		var sampleRate = streamOne.stream.meta.sampleRate;

		var i = 1;
		while (streams[i] != null) {
			var stream = streams[i];
			if (stream.stream.meta.channels != channels) throw "Channels are NOT equal!";
			if (sampleRate < stream.stream.meta.sampleRate) sampleRate = stream.stream.meta.sampleRate;
			var otherPCM:PCMData = Audio.decodeSamples(stream.stream, FLOAT_32, sampleRate);
			mixWith(pcm, otherPCM);
			i++;
		}

		final zero64:UInt64 = 0;

		if (pcm.size == zero64)
			return;

		switch (pcm.format) {
			case FLOAT_32:
				haxeal.bindings.AL.bufferData(buffer, channels == 2 ? 0x10011 : 0x10010, pcm.data, pcm.size, sampleRate);

			case INT_16:
				haxeal.bindings.AL.bufferData(buffer, channels == 2 ? HaxeAL.FORMAT_STEREO16 : HaxeAL.FORMAT_MONO16, pcm.data, pcm.size, sampleRate);
		}

		Native.free(pcm.data);
	}

	function mixWith(pcm:PCMData, otherPCM:PCMData) {
		
	}
}

@:publicFields
@:unreflective
class AudioStreamWrapper {
	var stream:cpp.Struct<AudioStream>;

	function new(s:cpp.Struct<AudioStream>) {
		stream = s;
	}
}

/**
 * Lime version
 * DOES NOT FUCKING WORK DO NOT TRY THIS
 */
/*
package;

import lime.app.Application;

import cpp.Native;
import cpp.Star;
import cpp.Pointer;

import cpp.UInt32;
import cpp.UInt64;

import lime.media.openHaxeAL.*;
import lime.utils.ArrayBufferView;

import cherry.Audio;

@:access(lime._internHaxeAL.backend.native.NativeCFFI)
class Main extends Application {
	public function new() {
		super();

		var gain:Float = 1.0;
		var filePath:String = "assets/sneaky.wav";
		var args:Array<String> = Sys.args();

		if (args.length > 0) {
			filePath = args[0];

			if (args.length > 1)
				gain = Std.parseFloat(args[1]);
		}

		final defaultDeviceName:String = HaxeALC.getString(null, HaxeALC.DEFAULT_DEVICE_SPECIFIER);
		final device:ALDevice = HaxeALC.openDevice(defaultDeviceName);

		final context:HaxeALContext = HaxeALC.createContext(device, [0x1992, 0]);

		if (!HaxeALC.makeContextCurrent(context)) {
			trace("Failed to make OpenAL context current");
			Sys.exit(1);
		}

		HaxeAL.listenerf(HaxeAL.GAIN, gain);

		trace('Streaming \'${filePath}\' (OpenAL)');

		final source:ALSource = HaxeAL.genSources(1)[0];

		final bufferCount:Int = 4;
		final desiredPCMFormat:PCMFormat = FLOAT_32;
		final zero64:UInt64 = 0;

		final buffers:Array<ALBuffer> = HaxeAL.genBuffers(bufferCount);

		final stream:AudioStream = Audio.streamFile(filePath, DETECT);

		for (i in 0...bufferCount) {
			final buffer:ALBuffer = buffers[i];
			final pcm:PCMData = Audio.decodeSamples(stream, desiredPCMFormat, stream.meta.sampleRate);

			if (pcm.size == zero64)
				break;

			var ptr:Pointer<Int> = Pointer.fromRaw(cast pcm.data);
			var arr:Array<Int> = ptr.toUnmanagedArray(pcm.size);

			switch (pcm.format) {
				case FLOAT_32:
					lime._internHaxeAL.backend.native.NativeCFFI.lime_al_buffer_data(
						buffer, (stream.meta.channels == 2) ? 0x10011 : 0x10010, arr, pcm.size, stream.meta.sampleRate
					);

				case INT_16:
					lime._internHaxeAL.backend.native.NativeCFFI.lime_al_buffer_data(
						buffer, (stream.meta.channels == 2) ? HaxeAL.FORMAT_STEREO16 : HaxeAL.FORMAT_MONO16, arr, pcm.size, stream.meta.sampleRate
					);
			}

			Native.free(pcm.data);
			HaxeAL.sourceQueueBuffers(source, 1, buffer);
		}

		HaxeAL.sourcePlay(source);

		sys.thread.Thread.create(() -> {
			while (true) {
				Sys.sleep(0.001);

				if (HaxeAL.getSourcei(source, HaxeAL.SOURCE_STATE) != HaxeAL.PLAYING) continue;

				while (HaxeAL.getSourcei(source, HaxeAL.BUFFERS_PROCESSED) > 0) {
					final buffer:ALBuffer = HaxeAL.genBuffers(1)[0];
					HaxeAL.sourceUnqueueBuffers(source, 1);

					final pcm:PCMData = Audio.decodeSamples(stream, desiredPCMFormat, stream.meta.sampleRate);
					if (pcm.size == zero64)
						break;

					var ptr:Pointer<Int> = Pointer.fromRaw(cast pcm.data);
					var arr:Array<Int> = ptr.toUnmanagedArray(pcm.size);

					switch (pcm.format) {
						case FLOAT_32:
							lime._internHaxeAL.backend.native.NativeCFFI.lime_al_buffer_data(
								buffer, (stream.meta.channels == 2) ? 0x10011 : 0x10010, arr, pcm.size, stream.meta.sampleRate
							);

						case INT_16:
							lime._internHaxeAL.backend.native.NativeCFFI.lime_al_buffer_data(
								buffer, (stream.meta.channels == 2) ? HaxeAL.FORMAT_STEREO16 : HaxeAL.FORMAT_MONO16, arr, pcm.size, stream.meta.sampleRate
							);
					}

					Native.free(pcm.data);
					HaxeAL.sourceQueueBuffers(source, 1, buffer);
				}
			}
		});

		while (true) {
			Sys.sleep(1 / 60);
		}

		Audio.streamClose(stream);

		HaxeAL.deleteSource(source);
		HaxeAL.deleteBuffers(buffers);

		HaxeALC.destroyContext(context);
		HaxeALC.closeDevice(device);
	}
}
*/