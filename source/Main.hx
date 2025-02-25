package;

import lime.app.Application;
import lime.ui.KeyCode;

class Main extends Application {
	override public function onWindowCreate() {
		trace('Heyyo');

		var gain:Float = 1.0;
		var filePath:String = "assets/sneaky.wav";
		var args:Array<String> = Sys.args();

		SoundManager.init();

		if (args.length == 0) {
			SoundManager.load(filePath, "sneaky");
			var snd = SoundManager.get("sneaky");
			snd.play();
			trace(snd.length);
		} else {
			SoundManager.loadMultiple(args, "sneaky");
			var snd = SoundManager.get("sneaky");
			snd.play();
			trace(snd.length);
		}

		Application.current.window.onKeyDown.add(keyDownEvt);
	}

	function keyDownEvt(code:KeyCode, _:Int) {
		var snd = SoundManager.get("sneaky");
		switch (code) {
			case KeyCode.LEFT:
				trace(snd.time);
				snd.time -= 1000;
				trace(snd.time);
			case KeyCode.RIGHT:
				trace(snd.time);
				snd.time += 1000;
				trace(snd.time);
			default:
		}
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

import lime.media.openal.*;
import lime.utils.ArrayBufferView;

import cherry.Audio;

@:access(lime._internal.backend.native.NativeCFFI)
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

		final defaultDeviceName:String = ALC.getString(null, ALC.DEFAULT_DEVICE_SPECIFIER);
		final device:ALDevice = ALC.openDevice(defaultDeviceName);

		final context:ALContext = ALC.createContext(device, [0x1992, 0]);

		if (!ALC.makeContextCurrent(context)) {
			trace("Failed to make OpenAL context current");
			Sys.exit(1);
		}

		AL.listenerf(AL.GAIN, gain);

		trace('Streaming \'${filePath}\' (OpenAL)');

		final source:ALSource = AL.genSources(1)[0];

		final bufferCount:Int = 4;
		final desiredPCMFormat:PCMFormat = FLOAT_32;
		final zero64:UInt64 = 0;

		final buffers:Array<ALBuffer> = AL.genBuffers(bufferCount);

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
					lime._internal.backend.native.NativeCFFI.lime_al_buffer_data(
						buffer, (stream.meta.channels == 2) ? 0x10011 : 0x10010, arr, pcm.size, stream.meta.sampleRate
					);

				case INT_16:
					lime._internal.backend.native.NativeCFFI.lime_al_buffer_data(
						buffer, (stream.meta.channels == 2) ? AL.FORMAT_STEREO16 : AL.FORMAT_MONO16, arr, pcm.size, stream.meta.sampleRate
					);
			}

			Native.free(pcm.data);
			AL.sourceQueueBuffers(source, 1, buffer);
		}

		AL.sourcePlay(source);

		sys.thread.Thread.create(() -> {
			while (true) {
				Sys.sleep(0.001);

				if (AL.getSourcei(source, AL.SOURCE_STATE) != AL.PLAYING) continue;

				while (AL.getSourcei(source, AL.BUFFERS_PROCESSED) > 0) {
					final buffer:ALBuffer = AL.genBuffers(1)[0];
					AL.sourceUnqueueBuffers(source, 1);

					final pcm:PCMData = Audio.decodeSamples(stream, desiredPCMFormat, stream.meta.sampleRate);
					if (pcm.size == zero64)
						break;

					var ptr:Pointer<Int> = Pointer.fromRaw(cast pcm.data);
					var arr:Array<Int> = ptr.toUnmanagedArray(pcm.size);
		
					switch (pcm.format) {
						case FLOAT_32:
							lime._internal.backend.native.NativeCFFI.lime_al_buffer_data(
								buffer, (stream.meta.channels == 2) ? 0x10011 : 0x10010, arr, pcm.size, stream.meta.sampleRate
							);
		
						case INT_16:
							lime._internal.backend.native.NativeCFFI.lime_al_buffer_data(
								buffer, (stream.meta.channels == 2) ? AL.FORMAT_STEREO16 : AL.FORMAT_MONO16, arr, pcm.size, stream.meta.sampleRate
							);
					}

					Native.free(pcm.data);
					AL.sourceQueueBuffers(source, 1, buffer);
				}
			}
		});

		while (true) {
			Sys.sleep(1 / 60);
		}

		Audio.streamClose(stream);

		AL.deleteSource(source);
		AL.deleteBuffers(buffers);

		ALC.destroyContext(context);
		ALC.closeDevice(device);
	}
}
*/